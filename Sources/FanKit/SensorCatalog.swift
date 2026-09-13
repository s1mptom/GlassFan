import Foundation
import Darwin

/// Sections of the sensor list, in the order they are shown: what matters to a
/// fan-control user first, the plumbing last.
public enum SensorGroup: String, Codable, Sendable, CaseIterable, Identifiable {
    case cpu, gpu, memory, cooling, storage, battery, comfort, power, board, other
    public var id: String { rawValue }

    /// Position in the list; the declaration order is the order of importance.
    public var rank: Int { Self.allCases.firstIndex(of: self)! }

    public var title: String {
        switch self {
        case .cpu:     return L10n.t("Процессор", "CPU")
        case .gpu:     return L10n.t("Графика", "GPU")
        case .memory:  return L10n.t("Память", "Memory")
        case .cooling: return L10n.t("Охлаждение", "Cooling")
        case .storage: return L10n.t("Накопитель", "Storage")
        case .battery: return L10n.t("Батарея", "Battery")
        case .comfort: return L10n.t("Корпус", "Chassis")
        case .power:   return L10n.t("Питание", "Power")
        case .board:   return L10n.t("Плата", "Logic board")
        case .other:   return L10n.t("Прочее", "Other")
        }
    }

    /// Short form for the headline row, where the column is narrow.
    public var shortTitle: String {
        switch self {
        case .cpu:     return L10n.t("Процессор", "CPU")
        case .gpu:     return L10n.t("Графика", "GPU")
        case .memory:  return L10n.t("Память", "Memory")
        case .cooling: return L10n.t("Радиатор", "Heatsink")
        case .storage: return L10n.t("Диск", "Storage")
        case .battery: return L10n.t("Батарея", "Battery")
        case .comfort: return L10n.t("Корпус", "Chassis")
        case .power:   return L10n.t("Питание", "Power")
        case .board:   return L10n.t("Плата", "Board")
        case .other:   return L10n.t("Прочее", "Other")
        }
    }
}

public struct SensorInfo: Sendable, Equatable, Identifiable, Hashable {
    public let key: String
    public let group: SensorGroup
    public let name: String
    /// One of the sensors worth showing to someone who is not reverse-engineering
    /// the SMC: a named core, a named part, the hottest probe of each triplet.
    /// Everything else - the other probes of a triplet, board diodes, virtual
    /// sensors, anything unnamed - is only listed under "All".
    public let essential: Bool
    /// Place in its group's fixed order. Unnamed sensors come last, by key.
    public let order: Int
    public var id: String { key }

    public init(key: String, group: SensorGroup, name: String, essential: Bool = false, order: Int = .max) {
        self.key = key
        self.group = group
        self.name = name
        self.essential = essential
        self.order = order
    }
}

/// Which naming table applies. Core, GPU and memory sensors sit at different keys
/// on each generation of Apple silicon, so a table read off one generation would
/// put wrong names on another; outside the families listed here, those sensors
/// keep generic names rather than borrowed ones.
public enum ChipFamily: Sendable, Hashable {
    /// M1, M1 Pro, M1 Max, M1 Ultra.
    case m1
    case other

    public static let current: ChipFamily = {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return .other }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0) == 0 else { return .other }
        let brand = String(cString: bytes)
        return brand.range(of: #"\bM1\b"#, options: .regularExpression) != nil ? .m1 : .other
    }()
}

/// Human names for the SMC's temperature keys.
///
/// Sources, cross-checked against a live M1 Max (MacBookPro18,2, 228 keys):
/// - Stats (github.com/exelban/stats, Modules/Sensors/values.swift) - the M1
///   family's cores, GPU clusters and memory, and several board-level keys.
/// - iSMC (github.com/dkorunic/iSMC, src/temp.txt) - most of the rest, with notes
///   on how the keys are laid out.
///
/// Where the two agree the name is used as is: the M1 family's ten CPU cores
/// (2 efficiency, 8 performance) and four GPU clusters are assigned to the same
/// keys by both. Each core is a triplet of keys - iSMC documents the layout as
/// probe, probe, max, and on this machine the third reading is the highest of the
/// three every time - so the core's row shows the max, and the two probes are
/// listed under "All". Stats takes the middle key instead; the max is what
/// matters for cooling.
///
/// Where they disagree or only one speaks, the choice is noted beside the key.
public enum SensorCatalog {

    public static func info(for key: String) -> SensorInfo {
        info(for: key, family: .current)
    }

    /// Memoised, because the interface asks this constantly: a couple of hundred
    /// sensors, on every redraw of the list. The answer for a key never changes.
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: [ChipFamily: [String: SensorInfo]] = [:]

    public static func info(for key: String, family: ChipFamily) -> SensorInfo {
        cacheLock.lock()
        let hit = cache[family]?[key]
        cacheLock.unlock()
        if let hit { return hit }

        let value = table(for: family)[key]
            ?? { let group = groupByPrefix(key); return SensorInfo(key: key, group: group, name: generatedName(for: key, group: group)) }()

        cacheLock.lock()
        cache[family, default: [:]][key] = value
        cacheLock.unlock()
        return value
    }

    // MARK: Tables

    private static let tablesLock = NSLock()
    nonisolated(unsafe) private static var tables: [ChipFamily: [String: SensorInfo]] = [:]

    private static func table(for family: ChipFamily) -> [String: SensorInfo] {
        tablesLock.lock()
        defer { tablesLock.unlock() }
        if let built = tables[family] { return built }
        // The family's table first: its named parts lead their groups, ahead of
        // the keys every chip shares.
        let entries = (family == .m1 ? m1() : []) + common()
        var table: [String: SensorInfo] = [:]
        for (index, entry) in entries.enumerated() where table[entry.key] == nil {
            table[entry.key] = SensorInfo(key: entry.key, group: entry.group,
                                          name: L10n.t(entry.ru, entry.en),
                                          essential: entry.essential, order: index)
        }
        tables[family] = table
        return table
    }

    private struct Entry {
        let key: String, group: SensorGroup, ru: String, en: String, essential: Bool
        init(_ key: String, _ group: SensorGroup, _ ru: String, _ en: String, essential: Bool = false) {
            self.key = key; self.group = group; self.ru = ru; self.en = en; self.essential = essential
        }
    }

    /// The SMC's key alphabet, in which the triplets step four characters at a time.
    private static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")

    private static func key(_ prefix: String, _ base: Character, plus offset: Int) -> String {
        let index = alphabet.firstIndex(of: base)! + offset
        return prefix + String(alphabet[index])
    }

    /// A max key and its probes, named after the part. Order of entries is the
    /// order they appear: the max first, so it leads its probes under "All".
    private static func triplet(_ prefix: String, base: Character, group: SensorGroup,
                                ru: String, en: String, essential: Bool = true, width: Int = 3) -> [Entry] {
        var entries = [Entry(key(prefix, base, plus: width - 1), group, ru, en, essential: essential)]
        for probe in 0..<(width - 1) {
            entries.append(Entry(key(prefix, base, plus: probe), group,
                                 "\(ru) · зонд \(probe + 1)", "\(en) · probe \(probe + 1)"))
        }
        return entries
    }

    /// The M1 family: M1, M1 Pro, M1 Max, M1 Ultra.
    private static func m1() -> [Entry] {
        var e: [Entry] = []

        // Cores, in the order both sources number them. Triplet bases on "Tp0".
        let cores: [(Character, String, String)] = [
            ("0", "Производительное ядро 1", "Performance core 1"),
            ("4", "Производительное ядро 2", "Performance core 2"),
            ("C", "Производительное ядро 3", "Performance core 3"),
            ("G", "Производительное ядро 4", "Performance core 4"),
            ("K", "Производительное ядро 5", "Performance core 5"),
            ("O", "Производительное ядро 6", "Performance core 6"),
            ("W", "Производительное ядро 7", "Performance core 7"),
            ("a", "Производительное ядро 8", "Performance core 8"),
            ("8", "Энергоэффективное ядро 1", "Efficiency core 1"),
            ("S", "Энергоэффективное ядро 2", "Efficiency core 2"),
        ]
        e += [Entry("TCMz", .cpu, "CPU, максимум", "CPU max", essential: true),
              Entry("TCMb", .cpu, "CPU, среднее", "CPU average", essential: true)]
        for (base, ru, en) in cores { e += triplet("Tp0", base: base, group: .cpu, ru: ru, en: en) }
        e += [Entry("TCDX", .cpu, "CPU, сводный по кристаллу", "CPU die aggregate"),
              Entry("Te00", .cpu, "Кристалл CPU, зона 1", "CPU die zone 1"),
              Entry("Te01", .cpu, "Кристалл CPU, зона 2", "CPU die zone 2"),
              Entry("Te02", .cpu, "Кристалл CPU, зона 3", "CPU die zone 3"),
              Entry("TCHP", .cpu, "Возле CPU", "CPU proximity")]

        // GPU clusters: pairs on "Tg0", probe then the hotter reading.
        for (n, base) in ["4", "C", "K", "S"].enumerated() {
            e += triplet("Tg0", base: Character(base), group: .gpu,
                         ru: "GPU, кластер \(n + 1)", en: "GPU cluster \(n + 1)", width: 2)
        }

        // Memory: triplets on "Tm0". Stats picks Tm02, Tm06, Tm08, Tm09 - the first
        // two agree with the triplet layout, the last two do not; the layout wins.
        for (n, base) in ["0", "4", "8", "C"].enumerated() {
            e += triplet("Tm0", base: Character(base), group: .memory, ru: "Память \(n + 1)", en: "Memory \(n + 1)")
        }

        // SoC heatsink: triplets on "Th0" (iSMC; the fifth is Max/Ultra only).
        for (n, base) in ["0", "4", "8", "C", "G"].enumerated() {
            e += triplet("Th0", base: Character(base), group: .cooling, ru: "Радиатор SoC \(n + 1)", en: "SoC heatsink \(n + 1)")
        }

        // SSD: triplets on "Ts0" (iSMC, M1 Pro/Max/Ultra).
        e += triplet("Ts0", base: "0", group: .storage, ru: "SSD 1", en: "SSD 1")
        e += triplet("Ts0", base: "4", group: .storage, ru: "SSD 2", en: "SSD 2")

        // Two more layouts neither source names. TC10-TC53 is a five-by-four grid
        // reading with the CPU (the first row 10-15 degrees above the rest); Td is
        // six triplets on the same probe/probe/max pattern, at board temperature.
        // Numbered, filed where the readings put them, never promoted.
        for row in 1...5 {
            for column in 0..<4 {
                e.append(Entry("TC\(row)\(column)", .cpu, "CPU, датчик \(row)·\(column + 1)", "CPU sensor \(row)·\(column + 1)"))
            }
        }
        for (n, base) in ["0", "4", "8", "C", "G", "K"].enumerated() {
            e += triplet("Td0", base: Character(base), group: .board,
                         ru: "Плата, группа \(n + 1)", en: "Board group \(n + 1)", essential: false)
        }

        // Ts0P and Ts1P: the Intel MacBook Pros' palm-rest sensors, and on this
        // M1 Max they read 31-33 C - skin temperature, twenty degrees below the SSD
        // dies. iSMC lists them as an SSD controller on the M1 family; the readings
        // do not fit that, so the older name stands, and it is the one inference
        // in this table rather than a sourced name.
        e += [Entry("Ts0P", .comfort, "Упор для рук 1", "Palm rest 1", essential: true),
              Entry("Ts1P", .comfort, "Упор для рук 2", "Palm rest 2", essential: true)]
        return e
    }

    /// Keys laid out the same across Apple silicon, per both sources.
    private static func common() -> [Entry] {
        var e: [Entry] = []

        e += [Entry("TG0H", .cooling, "Радиатор GPU", "GPU heatsink"),
              Entry("TaLP", .cooling, "Поток воздуха слева", "Airflow left", essential: true),
              Entry("TaRF", .cooling, "Поток воздуха справа", "Airflow right", essential: true)]

        // TG0B & co. are named GPU probes, but on Apple silicon they read with the
        // battery, not the GPU (33 C against GPU clusters at 58 C on this machine),
        // and iSMC notes they alias one another. Listed, never promoted.
        e += [Entry("TG0B", .gpu, "GPU, внешний зонд B0", "GPU external probe B0"),
              Entry("TG0C", .gpu, "GPU, внешний зонд C0", "GPU external probe C0"),
              Entry("TG0V", .gpu, "GPU, внешний зонд V0", "GPU external probe V0"),
              Entry("TG1B", .gpu, "GPU, внешний зонд B1", "GPU external probe B1"),
              Entry("TG2B", .gpu, "GPU, внешний зонд B2", "GPU external probe B2")]

        e += [Entry("TH0x", .storage, "Флеш-память (NAND)", "Flash storage (NAND)", essential: true),
              Entry("TH0a", .storage, "NVMe, канал A", "NVMe channel A"),
              Entry("TH0b", .storage, "NVMe, канал B", "NVMe channel B"),
              Entry("TS0P", .storage, "Возле SSD", "SSD proximity")]

        e += [Entry("TB0T", .battery, "Батарея", "Battery", essential: true),
              Entry("TB1T", .battery, "Батарея, датчик 1", "Battery sensor 1"),
              Entry("TB2T", .battery, "Батарея, датчик 2", "Battery sensor 2")]

        e += [Entry("TaLW", .comfort, "Корпус слева", "Chassis left", essential: true),
              Entry("TaRW", .comfort, "Корпус справа", "Chassis right", essential: true),
              Entry("TaLT", .comfort, "Возле Thunderbolt слева", "Thunderbolt left proximity"),
              Entry("TaRT", .comfort, "Возле Thunderbolt справа", "Thunderbolt right proximity")]

        e += [Entry("TPDX", .power, "Контроллеры питания, максимум", "Power delivery ICs, max", essential: true),
              Entry("TPSP", .power, "Возле блока питания", "Power supply proximity", essential: true),
              Entry("TSVR", .power, "Регулятор питания SoC V", "SoC regulator V"),
              Entry("TSWR", .power, "Регулятор питания SoC W", "SoC regulator W"),
              Entry("TSXR", .power, "Регулятор питания SoC X", "SoC regulator X"),
              Entry("TMVR", .power, "Регулятор питания памяти", "Memory voltage regulator"),
              Entry("TPMP", .power, "Возле управления питанием", "Power management proximity"),
              Entry("TPVD", .power, "Питание, диод напряжения", "Power voltage diode")]
        // iSMC numbers these 1-10, 11-16, 17-26 across the three runs of the alphabet.
        for (n, c) in "0123456789ABCDEFabcdefghij".enumerated() {
            e.append(Entry("TPD\(c)", .power, "Контроллер питания \(n + 1)", "Power delivery IC \(n + 1)"))
        }

        e += [Entry("TDEL", .board, "Плата, левый край", "Board, left edge"),
              Entry("TDER", .board, "Плата, правый край", "Board, right edge"),
              Entry("TDEC", .board, "Плата, край по центру", "Board, centre edge"),
              Entry("TDCR", .board, "Плата, центр справа", "Board, centre right"),
              Entry("TDeL", .board, "Плата, левый край 2", "Board, left edge 2"),
              Entry("TDeR", .board, "Плата, правый край 2", "Board, right edge 2"),
              Entry("TDBP", .board, "Плата, диод B", "Board diode B"),
              Entry("TDTP", .board, "Плата, диод T", "Board diode T"),
              Entry("TDVx", .board, "Плата, виртуальный", "Board, virtual")]
        for cluster in 0..<3 {
            for probe in 0..<5 {
                e.append(Entry("TD\(cluster)\(probe)", .board,
                               "Плата, диод \(cluster + 1)·\(probe + 1)", "Board diode \(cluster + 1)·\(probe + 1)"))
            }
        }

        e += [Entry("TW0P", .other, "Wi‑Fi", "Wi‑Fi", essential: true),
              Entry("TRDX", .other, "Радиочасть, максимум", "RF, max"),
              Entry("TR0Z", .other, "Радиочасть, опорный", "RF reference"),
              Entry("TR1d", .other, "Радиочасть, зонд 1", "RF probe 1"),
              Entry("TR2d", .other, "Радиочасть, зонд 2", "RF probe 2")]
        for (n, c) in "0123456789abcdefghij".enumerated() {
            e.append(Entry("TRD\(c)", .other, "Радиочасть, канал \(n + 1)", "RF channel \(n + 1)"))
        }
        e += [Entry("TVD0", .other, "Виртуальный: кристалл", "Virtual: die"),
              Entry("TVA0", .other, "Виртуальный: окружение", "Virtual: ambient"),
              Entry("TVV0", .other, "Виртуальный: напряжение", "Virtual: voltage"),
              Entry("TVSx", .other, "Виртуальный датчик, максимум", "Virtual sensor, max"),
              Entry("TVS0", .other, "Виртуальный датчик 1", "Virtual sensor 1"),
              Entry("TVS1", .other, "Виртуальный датчик 2", "Virtual sensor 2"),
              Entry("TVS2", .other, "Виртуальный датчик 3", "Virtual sensor 3"),
              Entry("TaTP", .other, "Воздух сверху", "Air, top"),
              Entry("TAOL", .other, "Воздух у крышки", "Air by the lid")]
        return e
    }

    // MARK: Unnamed keys

    private static func groupByPrefix(_ key: String) -> SensorGroup {
        switch true {
        case key.hasPrefix("Tp"), key.hasPrefix("TC"), key.hasPrefix("Te"): return .cpu
        case key.hasPrefix("Tg"), key.hasPrefix("TG"): return .gpu
        case key.hasPrefix("Tm"): return .memory
        case key.hasPrefix("Th"): return .cooling
        case key.hasPrefix("TB"): return .battery
        case key.hasPrefix("TH"): return .storage
        case key.hasPrefix("TP"), key.hasPrefix("TM"), key.hasPrefix("TS"): return .power
        case key.hasPrefix("TD"): return .board
        // No prefix earns the chassis group: "Ta" holds sensors twenty degrees
        // hotter than the case, and a wrong number under a heading people trust is
        // worse than no heading.
        default: return .other
        }
    }

    private static func generatedName(for key: String, group: SensorGroup) -> String {
        switch group {
        case .cpu:     return L10n.t("CPU, без названия", "CPU, unnamed")
        case .gpu:     return L10n.t("GPU, без названия", "GPU, unnamed")
        case .memory:  return L10n.t("Память, без названия", "Memory, unnamed")
        case .cooling: return L10n.t("Охлаждение, без названия", "Cooling, unnamed")
        case .storage: return L10n.t("Накопитель, без названия", "Storage, unnamed")
        case .battery: return L10n.t("Батарея, без названия", "Battery, unnamed")
        case .comfort: return L10n.t("Корпус, без названия", "Chassis, unnamed")
        case .power:   return L10n.t("Питание, без названия", "Power, unnamed")
        case .board:   return L10n.t("Плата, без названия", "Board, unnamed")
        case .other:   return L10n.t("Без названия", "Unnamed")
        }
    }

    // MARK: Ordering and defaults

    /// The fixed order of the list: group, then place in the table, then key.
    /// Readings play no part, so nothing moves while temperatures change.
    public static func precedes(_ a: String, _ b: String) -> Bool {
        precedes(info(for: a), info(for: b))
    }

    public static func precedes(_ x: SensorInfo, _ y: SensorInfo) -> Bool {
        if x.group != y.group { return x.group.rank < y.group.rank }
        if x.order != y.order { return x.order < y.order }
        return x.key < y.key
    }

    /// What a group is summed up by: its hottest essential sensor, or where the
    /// group has none, its hottest sensor of any kind. Probes and aliases stay out
    /// of a headline whenever a named part can speak for the group - an alias that
    /// happens to run hot is not "the GPU".
    public static func headlines(_ sensors: [SensorReading], groups: [SensorGroup]) -> [(SensorGroup, Double)] {
        var essential: [SensorGroup: Double] = [:]
        var any: [SensorGroup: Double] = [:]
        for sensor in sensors {
            let info = info(for: sensor.key)
            any[info.group] = max(any[info.group] ?? -.infinity, sensor.value)
            if info.essential {
                essential[info.group] = max(essential[info.group] ?? -.infinity, sensor.value)
            }
        }
        return groups.compactMap { group in
            guard let value = essential[group] ?? any[group] else { return nil }
            return (group, value)
        }
    }

    /// Display names for `keys`, in order, made distinct where they collide.
    ///
    /// Unnamed keys share a generated name per group. Side by side that is two
    /// lines nobody can tell apart - and anything that used the name as an
    /// identity merged them into one. Where a name is shared, the key goes after it.
    public static func distinctNames(for keys: [String]) -> [String] {
        let names = keys.map { info(for: $0).name }
        var counts: [String: Int] = [:]
        for name in names { counts[name, default: 0] += 1 }
        return zip(keys, names).map { key, name in
            (counts[name] ?? 0) > 1 ? "\(name) · \(key)" : name
        }
    }

    /// What to chart on a machine whose sensors are `available`.
    ///
    /// The known defaults where they exist. Where none do - a chip that names its
    /// sensors differently - this machine's own: a couple from the CPU and one
    /// from each of a few other groups, essential ones first, the same choice on
    /// every launch.
    public static func trackedDefaults(available: [String]) -> [String] {
        let present = Set(available)
        let known = defaultTracked.filter(present.contains)
        if !known.isEmpty { return known }

        var byGroup: [SensorGroup: [String]] = [:]
        for key in available.sorted(by: { a, b in
            let x = info(for: a), y = info(for: b)
            if x.essential != y.essential { return x.essential }
            return precedes(x, y)
        }) {
            byGroup[info(for: key).group, default: []].append(key)
        }
        let plan: [(SensorGroup, Int)] = [(.cpu, 2), (.gpu, 1), (.cooling, 1), (.comfort, 1), (.battery, 1)]
        return plan.flatMap { group, take in Array((byGroup[group] ?? []).prefix(take)) }
    }

    /// Charted out of the box on an M1-family Mac: CPU max and average, a GPU
    /// cluster, the SoC heatsink the fans cool, the palm rest, the battery.
    public static let defaultTracked = ["TCMz", "TCMb", "Tg05", "Th02", "Ts0P", "TB0T"]

    /// Earlier out-of-the-box charted sets. A config still holding one of these
    /// exactly was never customised, and gets the current defaults instead.
    private static let retiredDefaults: [Set<String>] = [
        ["TCMz", "Tp0D", "Tp0E", "TG0B", "Ts0P", "Ts1P", "TaLW", "TaRW", "TB0T", "TH0x"],
    ]

    public static func isRetiredDefault(_ keys: [String]) -> Bool {
        retiredDefaults.contains(Set(keys)) && keys.count == Set(keys).count
    }

    /// Keys that carry a temperature. The SMC has plenty of other 'T' keys that
    /// do not, including a few that pass for one by type and range.
    public static func looksLikeTemperature(key: String, type: String, value: Double) -> Bool {
        guard key.hasPrefix("T"), !nonTemperatures.contains(key) else { return false }
        guard type == "flt " || type == "ioft" else { return false }
        return value > 0 && value < 150
    }

    /// Read on this M1 Max: TVMD holds exactly 1.0, and the Ta05/Ta06/Ta0D/Ta0E
    /// set sits at 8-11 "degrees" in a warm, running laptop. Neither source names
    /// them; they are not temperatures.
    private static let nonTemperatures: Set<String> = ["TVMD", "Ta05", "Ta06", "Ta0D", "Ta0E"]
}

public enum L10n {
    public static let isRussian: Bool = {
        (Locale.preferredLanguages.first ?? "en").hasPrefix("ru")
    }()

    public static func t(_ ru: String, _ en: String) -> String { isRussian ? ru : en }
}
