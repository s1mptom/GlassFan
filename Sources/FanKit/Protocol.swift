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

    public init(index: Int, actualRPM: Double, targetRPM: Double, limits: FanLimits,
                mode: FanMode, forced: Bool, drivingTemp: Double?, emergency: Bool) {
        self.index = index
        self.actualRPM = actualRPM
        self.targetRPM = targetRPM
        self.limits = limits
        self.mode = mode
        self.forced = forced
        self.drivingTemp = drivingTemp
        self.emergency = emergency
    }

    public var id: Int { index }
}

public struct Snapshot: Codable, Equatable, Sendable {
    public var time: Double
    public var sensors: [SensorReading]
    public var fans: [FanReading]
    public var config: AppConfig
    public var daemonVersion: String

    public init(time: Double, sensors: [SensorReading], fans: [FanReading],
                config: AppConfig, daemonVersion: String) {
        self.time = time
        self.sensors = sensors
        self.fans = fans
        self.config = config
        self.daemonVersion = daemonVersion
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
