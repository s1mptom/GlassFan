import Foundation

public enum SensorGroup: String, Codable, Sendable, CaseIterable, Identifiable {
    case cpu, gpu, comfort, storage, battery, power, other
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cpu:     return L10n.t("Процессор", "CPU")
        case .gpu:     return L10n.t("Графика", "GPU")
        case .comfort: return L10n.t("Корпус и комфорт", "Chassis & comfort")
        case .storage: return L10n.t("Накопитель", "Storage")
        case .battery: return L10n.t("Батарея", "Battery")
        case .power:   return L10n.t("Питание", "Power")
        case .other:   return L10n.t("Прочее", "Other")
        }
    }

    /// Short form for the headline row, where the column is narrow.
    public var shortTitle: String {
        switch self {
        case .cpu:     return L10n.t("Процессор", "CPU")
        case .gpu:     return L10n.t("Графика", "GPU")
        case .comfort: return L10n.t("Корпус", "Chassis")
        case .storage: return L10n.t("Диск", "Storage")
        case .battery: return L10n.t("Батарея", "Battery")
        case .power:   return L10n.t("Питание", "Power")
        case .other:   return L10n.t("Прочее", "Other")
        }
    }

    public var symbol: String {
        switch self {
        case .cpu: return "cpu"
        case .gpu: return "cpu.fill"
        case .comfort: return "hand.raised"
        case .storage: return "internaldrive"
        case .battery: return "battery.100"
        case .power: return "bolt"
        case .other: return "thermometer.medium"
        }
    }
}

public struct SensorInfo: Sendable, Equatable, Identifiable, Hashable {
    public let key: String
    public let group: SensorGroup
    public let name: String
    public var id: String { key }

    public init(key: String, group: SensorGroup, name: String) {
        self.key = key
        self.group = group
        self.name = name
    }
}

/// Human names for the SMC keys worth showing. Anything unknown keeps its raw key and
/// is classified by prefix, so a sensor is never mislabelled - at worst it is unnamed.
public enum SensorCatalog {
    /// Memoised, because the interface asks this constantly.
    ///
    /// A machine reports a couple of hundred sensors and the sensors screen wants
    /// the group and the display name of every one of them on every redraw. An
    /// uncurated key builds its name from scratch, so without a cache a single
    /// pass over the list was thousands of small string allocations. The answer
    /// for a given key never changes, so it is worked out once.
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: [String: SensorInfo] = [:]

    public static func info(for key: String) -> SensorInfo {
        cacheLock.lock()
        let hit = cache[key]
        cacheLock.unlock()
        if let hit { return hit }

        let value: SensorInfo
        if let curated = curated[key] {
            value = SensorInfo(key: key, group: curated.0, name: curated.1)
        } else {
            let group = groupByPrefix(key)
            value = SensorInfo(key: key, group: group,
                               name: generatedName(for: key, group: group))
        }

        cacheLock.lock()
        cache[key] = value
        cacheLock.unlock()
        return value
    }

    private static func groupByPrefix(_ key: String) -> SensorGroup {
        switch true {
        case key.hasPrefix("Tp"), key.hasPrefix("TC"), key.hasPrefix("Te"): return .cpu
        case key.hasPrefix("TG"): return .gpu
        case key.hasPrefix("TB"): return .battery
        case key.hasPrefix("TH"): return .storage
        // No prefix earns the comfort group. Both "Ts" and "Ta" turned out to contain
        // sensors running 20 degrees hotter than the case (Ts02 at 57 C, TaTP at 54 C),
        // and a wrong number under a heading the user trusts is worse than no heading.
        // Only the curated keys above are treated as chassis sensors.
        case key.hasPrefix("TP"), key.hasPrefix("TM"), key.hasPrefix("TD"): return .power
        default: return .other
        }
    }

    private static func generatedName(for key: String, group: SensorGroup) -> String {
        switch group {
        case .cpu where key.hasPrefix("Tp"): return L10n.t("Ядро CPU", "CPU core")
        case .cpu:     return L10n.t("Кластер CPU", "CPU cluster")
        case .gpu:     return L10n.t("Датчик GPU", "GPU sensor")
        case .comfort: return L10n.t("Корпус", "Chassis")
        case .storage: return L10n.t("Накопитель", "Storage")
        case .battery: return L10n.t("Батарея", "Battery")
        case .power:   return L10n.t("Питание", "Power")
        case .other:   return L10n.t("Датчик", "Sensor")
        }
    }

    /// Only keys whose meaning was confirmed on this hardware get a specific name.
    private static let curated: [String: (SensorGroup, String)] = [
        "TCMz": (.cpu, L10n.t("CPU, горячая точка", "CPU hotspot")),
        "TCMb": (.cpu, L10n.t("CPU, подложка", "CPU substrate")),
        "TCDX": (.cpu, L10n.t("CPU, кристалл", "CPU die")),
        "TG0B": (.gpu, L10n.t("GPU", "GPU")),
        "TG0H": (.gpu, L10n.t("GPU, горячая точка", "GPU hotspot")),
        "TB0T": (.battery, L10n.t("Батарея 1", "Battery 1")),
        "TB1T": (.battery, L10n.t("Батарея 2", "Battery 2")),
        "TB2T": (.battery, L10n.t("Батарея 3", "Battery 3")),
        "TH0x": (.storage, L10n.t("SSD", "SSD")),
        "TH0a": (.storage, L10n.t("SSD, канал A", "SSD channel A")),
        "TH0b": (.storage, L10n.t("SSD, канал B", "SSD channel B")),
        // Chassis zones. Which physical spot each one sits under is not yet confirmed,
        // so they keep neutral names and the UI always shows the raw key beside them.
        "Ts0P": (.comfort, L10n.t("Корпус, зона 1", "Chassis zone 1")),
        "Ts1P": (.comfort, L10n.t("Корпус, зона 2", "Chassis zone 2")),
        "TaLW": (.comfort, L10n.t("Корпус, слева", "Chassis, left")),
        "TaRW": (.comfort, L10n.t("Корпус, справа", "Chassis, right")),
        "TaLT": (.comfort, L10n.t("Корпус, слева сверху", "Chassis, upper left")),
        "TaRT": (.comfort, L10n.t("Корпус, справа сверху", "Chassis, upper right")),
        "TAOL": (.comfort, L10n.t("Воздух на выходе", "Outlet air")),
    ]

    /// Sensors the daemon keeps history for out of the box.
    /// Display names for `keys`, in order, made distinct where they collide.
    ///
    /// Uncurated keys get a generated name per group, so every `Tp*` core is
    /// "CPU core". Side by side that is two lines nobody can tell apart - and
    /// anything that used the name as an identity merged them into one. Where a
    /// name is shared, the key goes after it.
    public static func distinctNames(for keys: [String]) -> [String] {
        let names = keys.map { info(for: $0).name }
        var counts: [String: Int] = [:]
        for name in names { counts[name, default: 0] += 1 }
        return zip(keys, names).map { key, name in
            (counts[name] ?? 0) > 1 ? "\(name) · \(key)" : name
        }
    }

    public static let defaultTracked = [
        "TCMz", "Tp0D", "Tp0E", "TG0B", "Ts0P", "Ts1P", "TaLW", "TaRW", "TB0T", "TH0x",
    ]

    /// Keys that carry a temperature. The SMC has plenty of other 'T' keys that do not.
    public static func looksLikeTemperature(key: String, type: String, value: Double) -> Bool {
        guard key.hasPrefix("T") else { return false }
        guard type == "flt " || type == "ioft" else { return false }
        return value > 0 && value < 150
    }
}

public enum L10n {
    public static let isRussian: Bool = {
        (Locale.preferredLanguages.first ?? "en").hasPrefix("ru")
    }()

    public static func t(_ ru: String, _ en: String) -> String { isRussian ? ru : en }
}
