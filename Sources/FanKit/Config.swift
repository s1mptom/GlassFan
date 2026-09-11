import Foundation

public enum FanMode: String, Codable, Sendable, CaseIterable {
    /// Hand the fan back to the system's own controller.
    case auto
    /// Hold a constant rpm.
    case fixed
    /// Follow the curve against the assigned sensors.
    case curve
}

/// The rpm range the SMC itself reports for a fan. Targets are always clamped to it.
public struct FanLimits: Codable, Equatable, Sendable {
    public var minRPM: Double
    public var maxRPM: Double

    public init(minRPM: Double, maxRPM: Double) {
        self.minRPM = minRPM
        self.maxRPM = maxRPM
    }

    public func clamp(_ rpm: Double) -> Double {
        Swift.min(Swift.max(rpm, minRPM), maxRPM)
    }
}

public struct FanSettings: Codable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var mode: FanMode
    public var fixedRPM: Double
    /// Keys of the sensors driving this fan. The hottest one wins.
    public var sensorKeys: [String]
    public var curve: FanCurve
    /// How far the temperature must fall before the target follows it down, in degrees.
    public var hysteresis: Double
    /// 0 applies the demand at once; values towards 1 ease into it.
    public var smoothing: Double

    public init(id: Int, mode: FanMode, fixedRPM: Double, sensorKeys: [String],
                curve: FanCurve, hysteresis: Double, smoothing: Double) {
        self.id = id
        self.mode = mode
        self.fixedRPM = fixedRPM
        self.sensorKeys = sensorKeys
        self.curve = curve
        self.hysteresis = hysteresis
        self.smoothing = smoothing
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        mode = try c.decodeIfPresent(FanMode.self, forKey: .mode) ?? .auto
        fixedRPM = try c.decodeIfPresent(Double.self, forKey: .fixedRPM) ?? 2000
        sensorKeys = try c.decodeIfPresent([String].self, forKey: .sensorKeys) ?? []
        curve = try c.decodeIfPresent(FanCurve.self, forKey: .curve) ?? FanCurve(points: [])
        hysteresis = min(max(try c.decodeIfPresent(Double.self, forKey: .hysteresis) ?? 2, 0), 20)
        smoothing = min(max(try c.decodeIfPresent(Double.self, forKey: .smoothing) ?? 0.3, 0), 0.95)
    }
}

public struct AppConfig: Codable, Equatable, Sendable {
    public var fans: [FanSettings]
    /// Above this temperature the curve is abandoned and the fan goes to full speed.
    public var emergencyTemp: Double
    /// Seconds between control ticks.
    public var pollInterval: Double
    /// Sensors the daemon records history for, beyond those assigned to fans.
    public var trackedSensors: [String]

    public static let emergencyRange: ClosedRange<Double> = 60...105
    public static let pollRange: ClosedRange<Double> = 0.25...10

    public init(fans: [FanSettings], emergencyTemp: Double, pollInterval: Double,
                trackedSensors: [String] = []) {
        self.fans = fans
        self.emergencyTemp = emergencyTemp.clamped(to: Self.emergencyRange)
        self.pollInterval = pollInterval.clamped(to: Self.pollRange)
        self.trackedSensors = trackedSensors
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            fans: try c.decodeIfPresent([FanSettings].self, forKey: .fans) ?? [],
            emergencyTemp: try c.decodeIfPresent(Double.self, forKey: .emergencyTemp) ?? 95,
            pollInterval: try c.decodeIfPresent(Double.self, forKey: .pollInterval) ?? 1,
            trackedSensors: try c.decodeIfPresent([String].self, forKey: .trackedSensors) ?? []
        )
    }

    public static func `default`(fanCount: Int) -> AppConfig {
        AppConfig(
            fans: (0..<fanCount).map {
                FanSettings(id: $0, mode: .auto, fixedRPM: 2000, sensorKeys: [],
                            curve: FanCurve(points: []), hysteresis: 2, smoothing: 0.3)
            },
            emergencyTemp: 95,
            pollInterval: 1,
            trackedSensors: SensorCatalog.defaultTracked
        )
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
