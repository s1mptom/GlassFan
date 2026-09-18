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

/// Why a fan is not being held when the settings say it should be.
///
/// Two different things that look the same from the interface and are not: one is a
/// write that never happened, the other a write that happened and changed nothing.
public enum FanWriteFailure: String, Codable, Sendable {
    /// The SMC would not take the write. Almost always: not running as root.
    case refused
    /// The SMC took it, reported success, and kept its own value. Seen on an M3 Pro
    /// whose fans went back to the system a couple of minutes after being pinned.
    case ignored
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
    /// Set when the last write to this fan did not take, so the UI can say so instead
    /// of claiming control it does not have. The text is for the log and the tooltip;
    /// `writeFailure` is what the interface should read.
    public var writeError: String?
    /// Absent from a daemon older than this field; `writeError` is then all there is.
    public var writeFailure: FanWriteFailure?
    /// The slowest this fan has been seen actually turning, once that has been watched
    /// often enough to believe. Absent until then, and on a fan never asked for less
    /// than it will do. See `FanFloor`.
    public var learnedFloor: Double?
    /// Taking the fan from the system, which on M3 and later is not instant: the
    /// thermal manager has to let go first, and that runs five to thirteen seconds.
    /// Not a failure and not yet a success, and it has to be told from both - reported
    /// as "write refused" it reads as something broken that the user should go and fix.
    public var acquiring: Bool?
    /// Which of the fan's curves set the target, when it is following curves. Absent
    /// from a daemon older than grouped curves.
    public var drivingCurve: Int?

    public init(index: Int, actualRPM: Double, targetRPM: Double, limits: FanLimits,
                mode: FanMode, forced: Bool, drivingTemp: Double?, emergency: Bool,
                writeError: String? = nil, writeFailure: FanWriteFailure? = nil,
                acquiring: Bool = false, learnedFloor: Double? = nil, drivingCurve: Int? = nil) {
        self.index = index
        self.actualRPM = actualRPM
        self.targetRPM = targetRPM
        self.limits = limits
        self.mode = mode
        self.forced = forced
        self.drivingTemp = drivingTemp
        self.emergency = emergency
        self.writeError = writeError
        self.writeFailure = writeFailure
        self.acquiring = acquiring ? true : nil
        self.learnedFloor = learnedFloor
        self.drivingCurve = drivingCurve
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
    /// The user has quit GlassFan on purpose. Hand the fans back to the system and
    /// stop applying the settings until someone opens the app again.
    ///
    /// Different from `releaseAll` in what it leaves behind: the panic button is a
    /// decision about the settings and rewrites them to auto, while this one is a
    /// decision about *now*. The modes and curves are untouched and come back with
    /// the app.
    ///
    /// Different from quitting in the other sense, too. A crash sends nothing, and a
    /// crash must not take the cooling with it - that is the whole reason the daemon
    /// outlives the app. Only a deliberate goodbye is a goodbye.
    case goodbye
}
