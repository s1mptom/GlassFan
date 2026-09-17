import Foundation

public struct SensorReading: Codable, Equatable, Sendable, Identifiable {
    public var key: String
    public var value: Double
    public var id: String { key }

    public init(key: String, value: Double) {
        self.key = key
        self.value = value
    }
}

public struct FanReading: Codable, Equatable, Sendable, Identifiable {
    public var index: Int
    public var actualRPM: Double
    public var targetRPM: Double
    public var limits: FanLimits
    public var mode: FanMode
    /// True while the daemon holds the fan away from the system's own control.
    public var forced: Bool
    /// Temperature currently steering the curve, when there is one.
    public var drivingTemp: Double?
    public var emergency: Bool
    /// Set when the last write to this fan was refused, so the UI can say so instead
    /// of claiming control it does not have.
    public var writeError: String?

    public init(index: Int, actualRPM: Double, targetRPM: Double, limits: FanLimits,
                mode: FanMode, forced: Bool, drivingTemp: Double?, emergency: Bool,
                writeError: String? = nil) {
        self.index = index
        self.actualRPM = actualRPM
        self.targetRPM = targetRPM
        self.limits = limits
        self.mode = mode
        self.forced = forced
        self.drivingTemp = drivingTemp
        self.emergency = emergency
        self.writeError = writeError
    }

    public var id: Int { index }
}

/// What the SMC's own fan control is aiming one of its zones at.
///
/// Not a reading and not something we set - it is the automatic control's setpoint,
/// reported so you can see what the machine would have done while you hold the fan
/// somewhere else. See `SensorCatalog.smcZoneTarget(key:)`.
public struct SMCZoneTarget: Codable, Equatable, Sendable, Identifiable {
    public var zone: Int
    public var target: Double
    public var id: Int { zone }

    public init(zone: Int, target: Double) {
        self.zone = zone
        self.target = target
    }
}

public struct Snapshot: Codable, Equatable, Sendable {
    public var time: Double
    public var sensors: [SensorReading]
    public var fans: [FanReading]
    public var config: AppConfig
    public var daemonVersion: String
    /// Absent from a daemon older than this field, and on hardware that reports no
    /// such keys - hence optional rather than an empty array meaning both.
    public var smcZoneTargets: [SMCZoneTarget]?
    /// The engine each sensor was found to answer to, once the daemon has watched
    /// the machine long enough to tell. Empty until then; see `EngineAffinity`.
    public var sensorEngines: [String: Engine]?

    public init(time: Double, sensors: [SensorReading], fans: [FanReading],
                config: AppConfig, daemonVersion: String,
                smcZoneTargets: [SMCZoneTarget]? = nil,
                sensorEngines: [String: Engine]? = nil) {
        self.time = time
        self.sensors = sensors
        self.fans = fans
        self.config = config
        self.daemonVersion = daemonVersion
        self.smcZoneTargets = smcZoneTargets
        self.sensorEngines = sensorEngines
    }
}

/// One point of recorded history. Only tracked sensors are kept, so this stays small.
public struct HistorySample: Codable, Equatable, Sendable {
    public var t: Double
    public var temps: [String: Double]
    public var fanRPM: [Double]

    public init(t: Double, temps: [String: Double], fanRPM: [Double]) {
        self.t = t
        self.temps = temps
        self.fanRPM = fanRPM
    }
}

public enum DaemonMessage: Codable, Sendable {
    case snapshot(Snapshot)
    case history([HistorySample])
    case failure(String)
}

public enum ClientCommand: Codable, Sendable {
    case hello
    case setConfig(AppConfig)
    /// Release every fan at once, whatever the config says. The panic button.
    case releaseAll
}
