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
/// put wrong names on another; outside the families listed here, those sensors are
/// named from the layout of the keys themselves rather than from a borrowed table.
///
/// The granularity differs on purpose. The M1 table covers a whole family because
/// both sources describe M1, M1 Pro, M1 Max and M1 Ultra as sharing it. The M3
/// entry covers the M3 Pro alone: it was measured on one, an M3 Pro has 6+6 cores
/// where an M3 has 4+4 and an M3 Max 12+4, and nothing here shows that the smaller
/// and larger dies put their clusters at the same keys. Until one is measured they
/// take the layout-derived names, which claim nothing a reading cannot back.
public enum ChipFamily: Sendable, Hashable {
    /// M1, M1 Pro, M1 Max, M1 Ultra.
    case m1
    /// M3 Pro. Measured on a MacBook Pro Mac15,7; see `m3Pro()`.
    case m3Pro
    case other

    public static let current: ChipFamily = from(brand: brandString)

    static var brandString: String {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0) == 0 else { return "" }
        return String(cString: bytes)
    }

    static func from(brand: String) -> ChipFamily {
        func has(_ pattern: String) -> Bool {
            brand.range(of: pattern, options: .regularExpression) != nil
        }
        if has(#"\bM1\b"#) { return .m1 }
        if has(#"\bM3 Pro\b"#) { return .m3Pro }
        return .other
    }

    /// How many CPU cores this Mac has, which is the one thing about the chip that
    /// does not have to be guessed. Used to check a guess rather than make one: see
    /// `SensorCatalog.discovered(_:engines:cores:)`.
    public static let physicalCores: Int = {
        var count: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("hw.physicalcpu", &count, &size, nil, 0) == 0 else { return 0 }
        return Int(count)
    }()
}

/// Human names for the SMC's temperature keys.
///
/// Sources, cross-checked against a live M1 Max (MacBookPro18,2, 228 keys):
/// - Stats (github.com/exelban/stats, Modules/Sensors/values.swift, MIT) - the M1
///   family's cores, GPU clusters and memory, and several board-level keys.
/// - iSMC (github.com/dkorunic/iSMC, src/temp.txt, MIT) - most of the rest, with
///   notes on how the keys are laid out.
/// - Asahi Linux's macsmc-hwmon (arch/arm64/boot/dts/apple/hwmon-*.dtsi,
///   GPL-2.0+ OR MIT) - the only labels here from people who reverse-engineered the
///   SMC protocol itself rather than guessing from readings. A short list: TH0x,
///   TB0T, TCHP, TW0P and the fan keys. It settled TCHP, which both the prefix and
///   the other two projects made look like the CPU; see `chargeRegulator`.
///
/// Where the sources agree the name is used as is: the M1 family's ten CPU cores
/// (2 efficiency, 8 performance) and four GPU clusters are assigned to the same
/// keys by both Stats and iSMC. Each core is a triplet of keys - iSMC documents the
/// layout as probe, probe, max, and on this machine the third reading is the highest
/// of the three every time - so the core's row shows the max, and the two probes are
/// listed under "All". Stats takes the middle key instead; the max is what
/// matters for cooling.
///
/// Where they disagree or only one speaks, the choice is noted beside the key.
///
/// What no source has is a chip past the M1 family. Stats' M3 table was checked
/// against the M3 Pro here and does not describe it: the keys it lists as
/// performance cores (Tf04, Tf09, Tf44 and the rest) are not on this machine at all,
/// it has no Tp entries for the generation although this chip's cores are plainly
/// Tp, and the Tf1 block it calls "GPU 1-4" followed a CPU load and not a GPU one.
/// Asahi has no M3 support. Hence the layout reader below, and `EngineAffinity`.
///
/// Chips with no table of their own are not left with a list of "unnamed": the
/// keys this machine actually reports are cut into the runs the SMC lays its
/// parts out in, and each run is named after its place in its prefix. See
/// `configure(_:)`.
public enum SensorCatalog {

    public static func info(for key: String) -> SensorInfo {
        info(for: key, family: .current)
    }

    /// What this Mac reports, so the parts no table names can still be read off the
    /// layout. Called by the daemon once it has probed the hardware, and by the app
    /// whenever a snapshot arrives - the app may well be looking at a machine whose
    /// sensors it has no table for.
    ///
    /// Readings, not just keys: telling where one part's run of keys ends and the
    /// next begins takes a look at the numbers. Recomputed only when the set of keys
    /// changes, never on a new reading - so the list is settled once and then holds
    /// still, and calling this every second costs a set comparison.
    public static func configure(_ readings: [SensorReading], engines: [String: Engine] = [:]) {
        let sorted = readings.sorted { $0.key < $1.key }
        let keys = sorted.map(\.key)
        tablesLock.lock()
        guard keys != layout.map(\.key) || engines != engineByKey else { tablesLock.unlock(); return }
        layout = sorted
        engineByKey = engines
        tables.removeAll()
        tablesLock.unlock()

        cacheLock.lock()
        cache.removeAll()
        cacheLock.unlock()
    }

    /// Memoised, because the interface asks this constantly: a couple of hundred
    /// sensors, on every redraw of the list. The answer for a key only changes when
    /// the machine's key list does, and that empties both caches.
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
    /// Set by `configure(_:)`; empty until the hardware has been read.
    nonisolated(unsafe) private static var layout: [SensorReading] = []
    /// Also set by `configure(_:)`: what the daemon learned about which engine each
    /// sensor answers to. Empty until it has watched the machine for a while, and on
    /// a machine whose engines never ran apart.
    nonisolated(unsafe) private static var engineByKey: [String: Engine] = [:]

    private static func table(for family: ChipFamily) -> [String: SensorInfo] {
        tablesLock.lock()
        defer { tablesLock.unlock() }
        if let built = tables[family] { return built }
        // Precedence, and with it the order of the list. The family's table first: a
        // name measured on the part beats one inferred from where its key sits. Then
        // the parts the layout can actually identify, so a core reads as a core and
        // leads its group. Then the keys every chip shares - sourced names, which
        // must not be displaced by a numbered run. The layout's leftovers last:
        // structure without a claim, and the only thing weaker than a shared key.
        let parts = discovered(layout, engines: engineByKey)
        let entries = familyTable(family) + parts.named + common() + parts.numbered
        var table: [String: SensorInfo] = [:]
        for (index, entry) in entries.enumerated() where table[entry.key] == nil {
            table[entry.key] = SensorInfo(key: entry.key, group: entry.group,
                                          name: L10n.t(entry.ru, entry.en),
                                          essential: entry.essential, order: index)
        }
        tables[family] = table
        return table
    }

    private static func familyTable(_ family: ChipFamily) -> [Entry] {
        switch family {
        case .m1:    return m1()
        case .m3Pro: return m3Pro()
        case .other: return []
        }
    }

    /// Internal rather than private so the layout reader can be tested as the pure
    /// function it is, without `configure(_:)` and the process-wide state
    /// that goes with it.
    struct Entry {
        let key: String, group: SensorGroup, ru: String, en: String, essential: Bool
        init(_ key: String, _ group: SensorGroup, _ ru: String, _ en: String, essential: Bool = false) {
            self.key = key; self.group = group; self.ru = ru; self.en = en; self.essential = essential
        }
    }

    /// The SMC's key alphabet, in which the triplets step four characters at a time.
    private static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
    private static let alphabetIndex: [Character: Int] =
        Dictionary(uniqueKeysWithValues: alphabet.enumerated().map { ($1, $0) })

    /// The key `offset` steps further along, carrying into the character before it.
    ///
    /// A run does not stop at the end of the alphabet: the M3 Pro has a triplet at
    /// Tp0y, Tp0z, **Tp10**. Stepping the last character alone walked off the end of
    /// a 62-character array there, so the step is done on the whole key.
    static func advance(_ key: String, by offset: Int) -> String? {
        guard offset >= 0 else { return nil }
        var characters = Array(key)
        var index = characters.count - 1
        var carry = offset
        while carry > 0 {
            guard index >= 0, let position = alphabetIndex[characters[index]] else { return nil }
            let total = position + carry
            characters[index] = alphabet[total % alphabet.count]
            carry = total / alphabet.count
            index -= 1
        }
        return String(characters)
    }

    private static func key(_ prefix: String, _ base: Character, plus offset: Int) -> String {
        advance(prefix + String(base), by: offset) ?? (prefix + String(base))
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

    // MARK: The layout this machine reports

    /// What a prefix is known to hold on every Apple silicon chip seen so far, and
    /// how a run under it should read.
    ///
    /// Only these five say what the part *is*. Which core sits at which key moves
    /// with every generation, but that a run of Tp keys is a core, and a run of Tg
    /// keys a GPU cluster, holds on both the M1 Max and the M3 Pro measured here and
    /// in both sources. Prefixes whose meaning does move - Ts reads with the SSD on
    /// an M1 and with the SoC on an M3 Pro - are deliberately absent: they are named
    /// by their table or not at all.
    ///
    /// The die zones are the one that is named without being promoted: the M1 table
    /// lists Te as plain entries, and a zone of the die is not a part anyone cools.
    private static let knownPrefixes: [String: (group: SensorGroup, ru: String, en: String, essential: Bool)] = [
        "Tp": (.cpu, "Ядро CPU", "CPU core", true),
        "Te": (.cpu, "Кристалл CPU, зона", "CPU die zone", false),
        "Tg": (.gpu, "GPU, кластер", "GPU cluster", true),
        "Tm": (.memory, "Память", "Memory", true),
        "Th": (.cooling, "Радиатор SoC", "SoC heatsink", true),
    ]

    /// The parts this machine's readings imply, for everything no table names.
    ///
    /// The SMC lays a part out as a run of consecutive keys - two or three of them,
    /// probes first and the reading that leads them last. Cutting the layout into
    /// those runs recovers the structure without knowing the chip: on the M3 Pro it
    /// finds 14 CPU cores, 9 GPU clusters, 4 SoC heatsinks and 5 die zones where the
    /// old code saw 137 sensors called "unnamed".
    ///
    /// Split in two because the two halves are worth different things. A run under a
    /// prefix `knownPrefixes` covers is a part, named and leading its group. A run
    /// under any other prefix is only structure - it says which readings belong
    /// together and which of them leads - so it is numbered, never promoted, and
    /// ranked below the keys every chip shares, whose names came from a source.
    static func discovered(_ layout: [SensorReading],
                           engines: [String: Engine] = [:],
                           cores: Int = ChipFamily.physicalCores) -> (named: [Entry], numbered: [Entry]) {
        var named: [Entry] = [], numbered: [Entry] = []
        // Numbered per engine and per prefix, so a part's number stays put as long as
        // the machine reports the same keys.
        var engineCounts: [Engine: Int] = [:]
        let byPrefix = Dictionary(grouping: layout.filter { $0.key.count == 4 && $0.key.hasPrefix("T") }) {
            String($0.key.prefix(2))
        }
        for prefix in byPrefix.keys.sorted() {
            var known = knownPrefixes[prefix]
            let found = runs(in: byPrefix[prefix] ?? [])
            // "Core" is a claim about how many there are, and the machine knows the
            // answer: hw.physicalcpu. On the M1 Max the Tp runs and the cores agree
            // exactly, ten and ten. On this M3 Pro there are seventeen runs and
            // twelve cores - some of them are cluster-level, or belong to parts of
            // the die this chip does not enable - so they are zones of the CPU here,
            // which is all the layout can honestly support.
            if prefix == "Tp", cores > 0, found.count != cores {
                known = (.cpu, "CPU, зона", "CPU zone", true)
            }
            for (index, run) in found.enumerated() {
                let ru: String, en: String, group: SensorGroup
                if let known {
                    let number = index + 1
                    group = known.group
                    ru = "\(known.ru) \(number)"
                    en = "\(known.en) \(number)"
                } else if let engine = agreedEngine(run, engines) {
                    // The prefix says nothing, but the machine does: this run heats
                    // when one engine spends and not when the others do.
                    let number = (engineCounts[engine] ?? 0) + 1
                    engineCounts[engine] = number
                    group = engine.group
                    ru = "\(engine.name), датчик \(number)"
                    en = "\(engine.name) sensor \(number)"
                } else {
                    group = groupByPrefix(run[0].key)
                    ru = "Группа \(prefix) \(index + 1)"
                    en = "\(prefix) group \(index + 1)"
                }
                var part = [Entry(run[run.count - 1].key, group, ru, en,
                                  essential: known?.essential ?? false)]
                for (probe, reading) in run.dropLast().enumerated() {
                    part.append(Entry(reading.key, group,
                                      "\(ru) · зонд \(probe + 1)", "\(en) · probe \(probe + 1)"))
                }
                if known != nil { named += part } else { numbered += part }
            }
        }

        // Keys with no neighbour to form a part with. A run's structure is worth
        // more than an engine's name, so these come last and only take a name where
        // nothing above gave them one.
        let placed = Set((named + numbered).map(\.key))
        for reading in layout.sorted(by: { rank($0.key) < rank($1.key) }) {
            guard !placed.contains(reading.key), let engine = engines[reading.key] else { continue }
            let number = (engineCounts[engine] ?? 0) + 1
            engineCounts[engine] = number
            numbered.append(Entry(reading.key, engine.group,
                                  "\(engine.name), датчик \(number)", "\(engine.name) sensor \(number)"))
        }
        return (named, numbered)
    }

    /// The engine a whole run answers to, when its keys agree.
    ///
    /// All of them, not a majority: the probes of one part sit within a millimetre of
    /// each other and answer to the same thing, so a run whose keys disagree is a run
    /// that was cut in the wrong place, and naming it after either answer would be
    /// dressing up a mistake.
    private static func agreedEngine(_ run: [SensorReading], _ engines: [String: Engine]) -> Engine? {
        guard let first = engines[run[0].key] else { return nil }
        return run.allSatisfy { engines[$0.key] == first } ? first : nil
    }

    /// The layout cut into parts: keys that step one at a time, broken wherever the
    /// reading falls.
    ///
    /// Adjacency alone is not enough. On the M3 Pro, Te0P through Te0V is seven
    /// consecutive keys holding three parts, and Tp0R through Tp0W is six holding
    /// two - cutting those every three characters put a part's coldest probe at its
    /// head. What marks the seam is the numbers: within a part they climb, probe to
    /// probe to the reading that leads it, and at a boundary they fall back to the
    /// next part's first probe. Te0Q reads 58.4 and Te0R 41.6; that is the seam.
    ///
    /// The fall has to be a big one. A seam is a drop of six to eighteen degrees -
    /// Te0Q to Te0R is 17.9, Tp0T to Tp0U is 8.4 - while inside a part the numbers
    /// do not always climb all the way: two probes of a cool part read identically,
    /// and the Tp0u and Tp0y parts of this M3 Pro end a degree or two *below* their
    /// second probe. A threshold of one degree cut those two parts in half and left
    /// a key stranded; `seam` sits clear of both kinds of movement.
    ///
    /// A part is capped at three, the widest either source describes. A key left
    /// alone by both rules is nobody's probe and is left out.
    private static let seam = 5.0

    private static func runs(in readings: [SensorReading]) -> [[SensorReading]] {
        let sorted = readings.sorted { rank($0.key) < rank($1.key) }
        var result: [[SensorReading]] = []
        var run: [SensorReading] = []
        func flush() {
            if run.count >= 2 { result.append(run) }
            run.removeAll()
        }
        for reading in sorted {
            if let last = run.last,
               rank(reading.key) != rank(last.key) + 1   // a gap in the keys
                || reading.value < last.value - seam     // or the seam between parts
                || run.count == 3 {                      // or a part already whole
                flush()
            }
            run.append(reading)
        }
        flush()
        return result
    }

    /// A key as the base-62 number its characters spell, so "next key along" is
    /// plain arithmetic and Tp0z is followed by Tp10.
    private static func rank(_ key: String) -> Int {
        key.reduce(0) { total, character in total * alphabet.count + (alphabetIndex[character] ?? 0) }
    }

    /// TCHP is not the CPU, on either chip here.
    ///
    /// Both the M1 and M3 Pro tables read it as "CPU proximity", which is what the
    /// two sensor projects imply and what the "TC" prefix suggests. Asahi Linux -
    /// who reverse-engineered the SMC protocol itself, and whose macsmc-hwmon driver
    /// labels it in `hwmon-laptop.dtsi` for every Apple silicon laptop they support -
    /// call it the charge regulator, and the readings here agree: through a load that
    /// took this M3 Pro's die from 48 to 67 C, TCHP moved between 1 and 4.
    private static let chargeRegulator =
        Entry("TCHP", .power, "Регулятор зарядки", "Charge regulator")

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
              Entry("Te02", .cpu, "Кристалл CPU, зона 3", "CPU die zone 3")]
        e += [chargeRegulator]

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

        return e
    }

    /// The M3 Pro, measured on a MacBook Pro Mac15,7 (6+6 cores, 18-core GPU) under
    /// macOS 26.6: 228 usable temperature keys, sampled at idle and under load.
    ///
    /// Short on purpose. Almost everything this chip reports is a run of keys that
    /// `discovered(_:)` already reads off the layout - 14 CPU cores, 9 GPU clusters,
    /// 4 SoC heatsinks - and repeating that here would only add a second place to
    /// get it wrong. What is here is what the layout cannot say and a measurement
    /// can. No key is named after a part that was not watched heating.
    ///
    /// Notably absent: which cores are the performance ones. One cluster was loaded
    /// at a time - a single default-QoS thread against a background-QoS one, three
    /// alternating rounds, each round centred on its own median so the machine's
    /// other work drifts out - and the die answers as a gradient rather than a split.
    /// The Te block and the Tp0u, Tp0y, Tp3S runs sit at the efficiency end in all
    /// three rounds; Tp3O and the Tp0U, Tp0a, Tp0g, Tp0m runs at the performance end
    /// in all three; and a third of the cores sit between them, changing sign from
    /// round to round. No boundary falls in the 6+6 this chip actually has. macOS
    /// offers no way to pin a thread to one core, so there is no sharper experiment
    /// to run, and the cores are numbered rather than labelled: a wrong
    /// "Performance core 3" would be worse than an honest "CPU core 3".
    private static func m3Pro() -> [Entry] {
        var e: [Entry] = []

        // The aggregates, verified against the cores they summarise: TCMz follows the
        // hottest core key for key, within 1 C of Tp3X across every sample, and TCMb
        // sits with the die.
        e += [Entry("TCMz", .cpu, "CPU, максимум", "CPU max", essential: true),
              Entry("TCMb", .cpu, "CPU, среднее", "CPU average", essential: true),
              chargeRegulator]

        // TCDX is not a CPU aggregate, whatever its prefix suggests: it is the hotter
        // of the SMC's two control zones. TCDX == max(Tf14, Tf24) held across 138
        // samples in four experiments, to 0.2 C - the width of the rounding in the
        // dump - and the two zones take turns: under a CPU load the CPU zone wins
        // every sample, under a GPU load the GPU zone wins most of them.
        e += [Entry("TCDX", .cooling, "Кристалл, максимум зон", "Die, hottest zone",
                    essential: true)]

        // Board sensors that answer to one engine and not the other. Under a CPU load
        // that lifted the die 19 C, TFD0/TFD1 and TSG1/TSG2 moved 1-2; under a GPU
        // load that lifted the clusters 17, they moved 10-15 and TED0/TED1 moved 5.
        // Proximity rather than a part: they follow an engine, and are not it.
        e += [Entry("TED0", .cpu, "Возле CPU 1", "CPU proximity 1"),
              Entry("TED1", .cpu, "Возле CPU 2", "CPU proximity 2"),
              Entry("TSCP", .cpu, "Возле CPU 3", "CPU proximity 3"),
              Entry("TFD0", .gpu, "Возле GPU 1", "GPU proximity 1"),
              Entry("TFD1", .gpu, "Возле GPU 2", "GPU proximity 2"),
              Entry("TSG1", .gpu, "Возле GPU 3", "GPU proximity 3"),
              Entry("TSG2", .gpu, "Возле GPU 4", "GPU proximity 4")]

        // Ts0 is not the SSD here. On the M1 family iSMC reads these as SSD dies, and
        // the M1 table names them so; on this M3 Pro they rise 7-16 C with the CPU
        // while the real flash keys (TH0x, TH0a, TH0b) *fall* half a degree under the
        // same load. They read with the SoC, and that is where they are filed.
        for (n, base) in ["0", "C", "K", "Y"].enumerated() {
            e += triplet("Ts0", base: Character(base), group: .cooling,
                         ru: "Зона SoC \(n + 1)", en: "SoC zone \(n + 1)")
        }
        e += triplet("Ts0", base: "h", group: .cooling, ru: "Зона SoC 5", en: "SoC zone 5", width: 2)

        // The SMC's own fan control, one block per zone - and the zones are the two
        // engines, not the two fans, which is what the numbering first suggested.
        // Loading each engine alone settles it: over an idle baseline, a CPU load
        // moved the Tf1 block 14 C and left Tf2 within 3.7, and a GPU load moved Tf2
        // by 15.1 and Tf1 by 5.1. Everything inside a block moves together within a
        // degree - one zone read several times over, not several parts.
        //
        // The readings stay; the control does not. The setpoint goes to
        // `smcZoneTarget`, the gains and flags to `nonTemperatures`.
        //
        // The six readings of a block are numbered rather than told apart. They
        // differ by a fraction of a degree in a fixed order, which reads like one
        // temperature at several filter lengths, but nothing here measured that, so
        // nothing here claims it.
        for (prefix, ru, en) in [("Tf1", "Зона SMC · CPU", "SMC zone · CPU"),
                                 ("Tf2", "Зона SMC · GPU", "SMC zone · GPU")] {
            e.append(Entry("\(prefix)4", .cooling, ru, en, essential: true))
            for (n, suffix) in ["8", "9", "A", "D", "E"].enumerated() {
                e.append(Entry("\(prefix)\(suffix)", .cooling,
                               "\(ru) · датчик \(n + 2)", "\(en) · reading \(n + 2)"))
            }
        }
        return e
    }

    /// What a control zone steers by, where that was measured. Numbered elsewhere:
    /// the zone count matching the fan count on this Mac is a coincidence worth not
    /// building on, and no other chip here has been loaded one engine at a time.
    public static func smcZoneName(_ zone: Int, family: ChipFamily = .current) -> String {
        guard family == .m3Pro, zone < m3ProZoneSubjects.count else {
            return L10n.t("Зона \(zone + 1)", "Zone \(zone + 1)")
        }
        return m3ProZoneSubjects[zone]
    }

    private static let m3ProZoneSubjects = ["CPU", "GPU"]

    /// Keys laid out the same across Apple silicon, per both sources.
    private static func common() -> [Entry] {
        var e: [Entry] = []

        // Ts0P and Ts1P: the Intel MacBook Pros' palm-rest sensors. On the M1 Max
        // they read 31-33 C - skin temperature, twenty degrees below the SSD dies -
        // and on the M3 Pro 31-33 C again, flat through a load that moves the SoC
        // 16 C. iSMC lists them as an SSD controller on the M1 family; the readings
        // do not fit that on either chip, so the older name stands, and it is the one
        // inference in this table rather than a sourced name.
        e += [Entry("Ts0P", .comfort, "Упор для рук 1", "Palm rest 1", essential: true),
              Entry("Ts1P", .comfort, "Упор для рук 2", "Palm rest 2", essential: true)]

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

        // "Hotspot" is Asahi's label, and it is the reason this one leads the group:
        // TB1T and TB2T are ordinary cells, TB0T is the worst of them.
        e += [Entry("TB0T", .battery, "Батарея, горячая точка", "Battery hotspot", essential: true),
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

        e += [Entry("TW0P", .other, "Wi‑Fi / Bluetooth", "Wi‑Fi / Bluetooth", essential: true),
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
        // A setpoint is in degrees and in range, and would sit at the top of the list
        // as the hottest thing on the machine. It is reported beside the fan instead.
        guard smcZoneTarget(key: key) == nil else { return false }
        guard type == "flt " || type == "ioft" else { return false }
        return value > 0 && value < 150
    }

    /// Read on this M1 Max: TVMD holds exactly 1.0, and the Ta05/Ta06/Ta0D/Ta0E
    /// set sits at 8-11 "degrees" in a warm, running laptop. Neither source names
    /// them; they are not temperatures.
    ///
    /// The rest is the SMC's fan control, read on an M3 Pro: Tf1* steers one fan and
    /// Tf2* the other, and within each block these four keys never move. Over 18
    /// samples spanning idle, an efficiency-cluster load and a load that took the
    /// CPU from 54 to 90 C, Tf11 held 3.2, Tf1C held 1.0, Tf15 held 26.4 and Tf10
    /// held 0.0, digit for digit - gains and flags, not readings. They are excluded
    /// because a constant in the sensor list is worse than an absence: it can be
    /// picked to drive a curve, and a curve driven by a constant never moves a fan.
    private static let nonTemperatures: Set<String> = [
        "TVMD", "Ta05", "Ta06", "Ta0D", "Ta0E",
        "Tf10", "Tf11", "Tf15", "Tf1C",
        "Tf20", "Tf21", "Tf25", "Tf2C",
    ]

    // MARK: What the SMC is steering by

    /// The temperature the SMC's own fan control is aiming its zone at, if this key
    /// holds one.
    ///
    /// `Tf16` = 79.6 and `Tf26` = 82.4 on the M3 Pro measured - the CPU zone's target
    /// and the GPU zone's - and both sat there through everything the machine was put
    /// through. The other constants of the block move with nothing either, but these
    /// two are in degrees and in range, so unlike them they read convincingly as the
    /// two hottest sensors on the machine, above the real CPU maximum. They are a
    /// setpoint. Kept out of the sensor list and shown beside the fans instead, where
    /// a target belongs: it is worth seeing what the automatic control would have
    /// done while you hold the fans yourself.
    public static func smcZoneTarget(key: String) -> Int? {
        guard key.count == 4, key.hasPrefix("Tf"), key.hasSuffix("6") else { return nil }
        guard let zone = Int(String(key[key.index(key.startIndex, offsetBy: 2)])), zone >= 1 else { return nil }
        return zone - 1
    }

    /// The zone targets among `readings`, by zone: `[0: 79.6, 1: 82.4]`.
    public static func smcZoneTargets(_ readings: [SensorReading]) -> [Int: Double] {
        var targets: [Int: Double] = [:]
        for reading in readings {
            if let zone = smcZoneTarget(key: reading.key) { targets[zone] = reading.value }
        }
        return targets
    }
}

public enum L10n {
    public static let isRussian: Bool = {
        (Locale.preferredLanguages.first ?? "en").hasPrefix("ru")
    }()

    public static func t(_ ru: String, _ en: String) -> String { isRussian ? ru : en }
}
