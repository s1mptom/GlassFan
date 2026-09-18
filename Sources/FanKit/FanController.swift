import Foundation

/// Turns sensor readings into a target rpm for one fan.
///
/// Pure state machine: the same inputs always give the same decision, so the whole
/// policy is testable without touching hardware. Returning nil means "release this
/// fan back to the system".
public struct FanController {
    public var settings: FanSettings
    public var limits: FanLimits

    /// Temperature that produced the target currently in force, for hysteresis.
    private var heldTemp: Double?
    /// Last target handed out, for smoothing.
    private var lastTarget: Double?

    public private(set) var lastDrivingTemp: Double?
    public private(set) var isEmergency = false

    public init(settings: FanSettings, limits: FanLimits) {
        self.settings = settings
        self.limits = limits
    }

    public mutating func reset() {
        heldTemp = nil
        lastTarget = nil
        isEmergency = false
    }

    public mutating func update(temperatures: [String: Double], emergencyTemp: Double) -> Double? {
        isEmergency = false

        switch settings.mode {
        case .auto:
            heldTemp = nil
            lastTarget = nil
            lastDrivingTemp = assignedMax(temperatures)
            return nil

        case .fixed:
            lastDrivingTemp = assignedMax(temperatures)
            let target = limits.clamp(settings.fixedRPM)
            lastTarget = target
            return target

        case .curve:
            guard let hottest = assignedMax(temperatures) else {
                // Nothing to steer by - safer to let the system have the fan back.
                heldTemp = nil
                lastTarget = nil
                lastDrivingTemp = nil
                return nil
            }
            lastDrivingTemp = hottest

            if hottest >= emergencyTemp {
                isEmergency = true
                heldTemp = hottest
                lastTarget = limits.maxRPM
                return limits.maxRPM
            }

            let effective = applyHysteresis(to: hottest)
            guard let demand = settings.curves[0].curve.rpm(at: effective) else {
                heldTemp = nil
                lastTarget = nil
                return nil
            }

            let clamped = limits.clamp(demand)
            let target = applySmoothing(to: clamped)
            lastTarget = target
            return target
        }
    }

    private func assignedMax(_ temperatures: [String: Double]) -> Double? {
        settings.allSensorKeys.compactMap { temperatures[$0] }.max()
    }

    /// Rises follow the temperature at once; falls wait until it has dropped past the band.
    private mutating func applyHysteresis(to temp: Double) -> Double {
        guard let held = heldTemp else {
            heldTemp = temp
            return temp
        }
        if temp > held || held - temp >= settings.hysteresis {
            heldTemp = temp
            return temp
        }
        return held
    }

    private func applySmoothing(to demand: Double) -> Double {
        guard settings.smoothing > 0, let previous = lastTarget else { return demand }
        return previous + (demand - previous) * (1 - settings.smoothing)
    }
}
