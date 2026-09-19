import Foundation

/// Turns sensor readings into a target rpm for one fan.
///
/// Pure state machine: the same inputs always give the same decision, so the whole
/// policy is testable without touching hardware. Returning nil means "release this
/// fan back to the system".
public struct FanController {
    public var settings: FanSettings {
        didSet {
            // Holds are kept by curve number. Remove a curve and the ones after it move
            // up a place; a hold carried over would be another group's temperature.
            if oldValue.curves.map(\.sensorKeys) != settings.curves.map(\.sensorKeys) { heldTemps = [:] }
        }
    }
    public var limits: FanLimits

    /// Per curve: the temperature that produced the demand it is holding, for hysteresis.
    /// Per curve because a cooling group must not drag another group's hold down with it.
    private var heldTemps: [Int: Double] = [:]
    /// Last target handed out, for smoothing.
    private var lastTarget: Double?

    public private(set) var lastDrivingTemp: Double?
    /// Which curve set the last target, while following curves.
    public private(set) var lastDrivingCurve: Int?
    public private(set) var isEmergency = false

    public init(settings: FanSettings, limits: FanLimits) {
        self.settings = settings
        self.limits = limits
    }

    public mutating func reset() {
        heldTemps = [:]
        lastDrivingCurve = nil
        lastTarget = nil
        isEmergency = false
    }

    public mutating func update(temperatures: [String: Double], emergencyTemp: Double) -> Double? {
        isEmergency = false

        switch settings.mode {
        case .auto:
            heldTemps = [:]
            lastTarget = nil
            lastDrivingTemp = assignedMax(temperatures)
            lastDrivingCurve = nil
            return nil

        case .fixed:
            lastDrivingTemp = assignedMax(temperatures)
            lastDrivingCurve = nil
            let target = limits.clamp(settings.fixedRPM)
            lastTarget = target
            return target

        case .curve:
            let temps = settings.curves.map { hottest(of: $0.sensorKeys, in: temperatures) }
            guard let hottestAnywhere = temps.compactMap({ $0 }).max() else {
                // Nothing to steer by - safer to let the system have the fan back.
                heldTemps = [:]
                lastTarget = nil
                lastDrivingTemp = nil
                lastDrivingCurve = nil
                return nil
            }

            if hottestAnywhere >= emergencyTemp {
                isEmergency = true
                let index = temps.firstIndex { $0 == hottestAnywhere }!
                heldTemps[index] = hottestAnywhere
                lastDrivingCurve = index
                lastDrivingTemp = hottestAnywhere
                lastTarget = limits.maxRPM
                return limits.maxRPM
            }

            // Each curve asks for a speed; the fan runs at the fastest. A tie goes to
            // the earlier curve, so the one reported does not flicker between equals.
            var winner: (index: Int, demand: Double)?
            for (index, rule) in settings.curves.enumerated() {
                guard let temp = temps[index] else { heldTemps[index] = nil; continue }
                let effective = applyHysteresis(to: temp, curve: index)
                guard let demand = rule.curve.rpm(at: effective) else { continue }
                if winner.map({ demand > $0.demand }) ?? true { winner = (index, demand) }
            }
            guard let winner else {
                heldTemps = [:]
                lastTarget = nil
                lastDrivingTemp = nil
                lastDrivingCurve = nil
                return nil
            }
            lastDrivingCurve = winner.index
            lastDrivingTemp = temps[winner.index]

            let target = applySmoothing(to: limits.clamp(winner.demand))
            lastTarget = target
            return target
        }
    }

    private func hottest(of keys: [String], in temperatures: [String: Double]) -> Double? {
        keys.compactMap { temperatures[$0] }.max()
    }

    private func assignedMax(_ temperatures: [String: Double]) -> Double? {
        hottest(of: settings.allSensorKeys, in: temperatures)
    }

    /// Rises follow the temperature at once; falls wait until it has dropped past the band.
    private mutating func applyHysteresis(to temp: Double, curve: Int) -> Double {
        guard let held = heldTemps[curve] else {
            heldTemps[curve] = temp
            return temp
        }
        if temp > held || held - temp >= settings.hysteresis {
            heldTemps[curve] = temp
            return temp
        }
        return held
    }

    private func applySmoothing(to demand: Double) -> Double {
        guard settings.smoothing > 0, let previous = lastTarget else { return demand }
        let eased = previous + (demand - previous) * (1 - settings.smoothing)
        // Easing only ever approaches. For a speed that does not matter; for a stop it
        // does: a target of 1e-23 rpm is not zero, the SMC runs a fan at its floor for
        // any target above zero, and a fan whose curve said stop kept turning.
        if abs(eased - demand) < 1 { return demand }
        // And under the fan's minimum a smaller target does not slow it - it sits at its
        // floor - so on the way down to a stop, once below the minimum, stop.
        if demand == 0, eased < limits.minRPM { return 0 }
        return eased
    }
}
