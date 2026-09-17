import Foundation

/// The engine a sensor's temperature answers to, learned on the machine itself.
///
/// The SMC's key names are undocumented and move with every generation, so a table
/// can only ever describe chips somebody has taken apart. The machine, though, says
/// how much energy each of its engines is spending, second by second and without any
/// privileges - IOReport's "Energy Model" group. A sensor that heats when the GPU
/// spends and not when the CPU does is on the GPU, whatever its key says, on a chip
/// nobody has catalogued.
public enum Engine: String, Codable, Sendable, CaseIterable {
    case cpu, gpu, memory, display, neural

    public var group: SensorGroup {
        switch self {
        case .cpu:     return .cpu
        case .gpu:     return .gpu
        case .memory:  return .memory
        case .display: return .other
        case .neural:  return .other
        }
    }

    public var name: String {
        switch self {
        case .cpu:     return L10n.t("CPU", "CPU")
        case .gpu:     return L10n.t("GPU", "GPU")
        case .memory:  return L10n.t("Память", "Memory")
        case .display: return L10n.t("Дисплей", "Display")
        case .neural:  return L10n.t("Neural Engine", "Neural Engine")
        }
    }

    /// Which engine one of IOReport's "Energy Model" channels belongs to.
    ///
    /// The per-core channels are summed into one CPU rather than kept apart. Keeping
    /// them apart was the plan - it would have told a performance core from an
    /// efficiency one, which no table here can - but it does not survive contact with
    /// the die: on an M3 Pro the efficiency cluster spends about a twentieth of what
    /// the performance cluster does, six cores away on the same piece of silicon, and
    /// three separate experiments could not pull the two apart in the temperatures.
    /// A cluster this code cannot tell apart is not one it should label.
    ///
    /// `_SRAM` and `DTL` channels are the same cores counted again, and the "… Energy"
    /// channels are totals that would count every engine they sum a second time.
    public static func forPowerChannel(_ name: String) -> Engine? {
        if name.hasSuffix("_SRAM") || name.contains("DTL") || name.hasSuffix("Energy") { return nil }
        if name.hasPrefix("PCPU") || name.hasPrefix("ECPU") { return .cpu }
        if name.hasPrefix("PCPM") || name.hasPrefix("ECPM") { return .cpu }
        switch name {
        case "GPU":                 return .gpu
        // AMCC is the memory controller and DCS the DRAM's own interface; both move
        // with DRAM and against nothing else, so they are one engine, not three.
        case "DRAM", "AMCC", "DCS": return .memory
        case "DISP", "DISPEXT":     return .display
        case "ANE":                 return .neural
        default:                    return nil
        }
    }
}

/// What the learner decided about one sensor, and how sure it is.
public struct EngineVerdict: Codable, Sendable, Equatable {
    public var engine: Engine
    /// The engine's share of the sensor's explained movement, 0...1.
    public var share: Double
    /// How much of the sensor's movement the engines explain at all, 0...1.
    public var fit: Double

    public init(engine: Engine, share: Double, fit: Double) {
        self.engine = engine
        self.share = share
        self.fit = fit
    }
}

/// Learns which engine each sensor answers to, from readings and per-engine power.
///
/// Entirely by watching. Nothing here runs a load, warms a machine or asks anyone to:
/// an ordinary day already drives the engines apart - a build runs the CPU, a video
/// call the image processor, a game the GPU - and the power meters say which was
/// which. Reading them costs one extra call on a tick the daemon was already taking.
///
/// Keeps statistics rather than samples: the sums needed to regress every sensor on
/// every engine, which is a few thousand doubles whatever the machine runs for, so a
/// month of uptime costs what a minute does.
///
/// Why a regression and not the obvious correlation of each sensor against each
/// engine. The engines do not take turns - a busy machine runs all of them - so a
/// GPU sensor correlates strongly with the CPU too, and picking the strongest
/// correlation put every GPU cluster on whichever engine happened to be busiest.
/// Regressing on all of them at once asks a different question: what does this
/// engine explain that the others do not.
///
/// Power is smoothed before it is used. A die has thermal mass: it answers the last
/// half minute of power, not this instant's, and unsmoothed power lines up with
/// nothing.
/// Not persisted. What survives a restart is the verdicts, which is the part worth
/// keeping: a half-learned machine finishes learning in another twenty minutes, and
/// carrying the statistics across an update would carry whatever was wrong with them.
public struct EngineAffinity: Sendable {
    /// Seconds of power a sensor's temperature reflects. Fitted on an M3 Pro across
    /// alternating idle, CPU, GPU and both loads: 15 s explained the cores and the
    /// GPU clusters best, 30 s the board sensors behind them, and 60 s nothing more.
    static let smoothingSeconds = 15.0

    private var channels: [Engine] = Engine.allCases
    private var smoothed: [Double]
    private var started = false

    private var samples = 0
    private var sumPower: [Double]
    private var sumPowerSquared: [[Double]]
    private var powerRange: [(low: Double, high: Double)]

    private var sumTemperature: [String: Double] = [:]
    private var sumTemperatureSquared: [String: Double] = [:]
    private var sumCross: [String: [Double]] = [:]
    private var temperatureRange: [String: (low: Double, high: Double)] = [:]
    /// Counted per sensor, because a covariance is only a covariance over one window.
    /// The engines' own statistics are kept over every tick, so a key that appeared
    /// late, or that failed to read once, has been through a different window and its
    /// sums cannot be centred against theirs - dividing them by the machine's tick
    /// count would put its mean somewhere it never was. Such a sensor is not judged
    /// rather than judged wrongly; the daemon reads one fixed list of keys every
    /// tick, so this is the flaky key's case, not the ordinary one.
    private var sensorSamples: [String: Int] = [:]

    public init() {
        let n = Engine.allCases.count
        smoothed = Array(repeating: 0, count: n)
        sumPower = Array(repeating: 0, count: n)
        sumPowerSquared = Array(repeating: Array(repeating: 0, count: n), count: n)
        powerRange = Array(repeating: (low: .infinity, high: -.infinity), count: n)
    }

    public var sampleCount: Int { samples }

    /// One tick: what each engine spent since the last one, and what every sensor
    /// reads now.
    public mutating func observe(power: [Engine: Double], temperatures: [String: Double],
                                 interval: TimeInterval = 1) {
        guard interval > 0 else { return }
        let alpha = 1 - exp(-interval / Self.smoothingSeconds)
        for (index, engine) in channels.enumerated() {
            let value = (power[engine] ?? 0) / interval
            smoothed[index] = started ? smoothed[index] + alpha * (value - smoothed[index]) : value
        }
        started = true

        samples += 1
        for i in channels.indices {
            sumPower[i] += smoothed[i]
            powerRange[i] = (min(powerRange[i].low, smoothed[i]), max(powerRange[i].high, smoothed[i]))
            for j in channels.indices { sumPowerSquared[i][j] += smoothed[i] * smoothed[j] }
        }
        for (key, value) in temperatures {
            sumTemperature[key, default: 0] += value
            sumTemperatureSquared[key, default: 0] += value * value
            sensorSamples[key, default: 0] += 1
            let range = temperatureRange[key] ?? (low: .infinity, high: -.infinity)
            temperatureRange[key] = (min(range.low, value), max(range.high, value))
            var cross = sumCross[key] ?? Array(repeating: 0, count: channels.count)
            for i in channels.indices { cross[i] += smoothed[i] * value }
            sumCross[key] = cross
        }
    }

    // MARK: Verdicts

    /// How long the machine has to be watched before any sensor is named from this.
    /// Twenty minutes at one reading a second: enough for an ordinary day's work to
    /// have run the engines apart at least once, and short enough to land inside one
    /// sitting at the machine.
    public static let minimumSamples = 1200
    /// A sensor that never moved has nothing to attribute, and a sensor the engines
    /// barely explain is answering to something not on the list - the room, the
    /// charger, the lid.
    ///
    /// The three bars below are set where a watched M3 Pro put them, and the fit is
    /// the one that matters. Across a run that loaded the CPU, the GPU and both, the
    /// fits came out in two clumps with nothing between: 0.57 to 0.76 for the chassis,
    /// the Wi-Fi module, the charge regulator and the radio - everything that merely
    /// warms when the machine warms - and 0.81 to 0.90 for the parts that actually sit
    /// on an engine. A bar at 0.8 lands in the gap. The share bar then drops what two
    /// engines heat about equally, like the sensor beside the SSD, which is not
    /// anybody's to name.
    public static let minimumSpan = 5.0
    static let minimumFit = 0.8
    static let minimumShare = 0.6
    /// An engine that never varied cannot have caused anything. The M3 Pro's image
    /// signal processor sat at 3 mJ/s for a whole run and, being all but constant,
    /// correlated beautifully with every GPU sensor on the machine.
    static let minimumPowerSpan = 200.0

    public func verdicts(minimumSamples: Int = EngineAffinity.minimumSamples) -> [String: EngineVerdict] {
        guard samples >= minimumSamples else { return [:] }
        let n = Double(samples)

        // The engines that actually moved, and the correlation between them.
        let live = channels.indices.filter {
            powerRange[$0].high - powerRange[$0].low >= Self.minimumPowerSpan
        }
        guard !live.isEmpty else { return [:] }
        let meanPower = live.map { sumPower[$0] / n }
        let sdPower = live.enumerated().map { index, i in
            (sumPowerSquared[i][i] / n - meanPower[index] * meanPower[index]).squareRoot()
        }
        guard sdPower.allSatisfy({ $0 > 0 }) else { return [:] }

        var gram = Array(repeating: Array(repeating: 0.0, count: live.count), count: live.count)
        for (a, i) in live.enumerated() {
            for (b, j) in live.enumerated() {
                let covariance = sumPowerSquared[i][j] / n - meanPower[a] * meanPower[b]
                gram[a][b] = covariance / (sdPower[a] * sdPower[b])
            }
        }

        var result: [String: EngineVerdict] = [:]
        for (key, sum) in sumTemperature {
            guard sensorSamples[key] == samples else { continue }
            guard let range = temperatureRange[key], range.high - range.low >= Self.minimumSpan,
                  let cross = sumCross[key], let squared = sumTemperatureSquared[key] else { continue }
            let mean = sum / n
            let sd = (squared / n - mean * mean).squareRoot()
            guard sd > 0 else { continue }
            let target = live.enumerated().map { index, i in
                (cross[i] / n - meanPower[index] * mean) / (sdPower[index] * sd)
            }

            let weights = Self.solve(gram: gram, target: target)
            let fit = zip(weights, target).reduce(0) { $0 + $1.0 * $1.1 }
            let total = weights.reduce(0, +)
            guard fit >= Self.minimumFit, total > 0 else { continue }
            guard let best = weights.indices.max(by: { weights[$0] < weights[$1] }) else { continue }
            let share = weights[best] / total
            guard share >= Self.minimumShare else { continue }
            result[key] = EngineVerdict(engine: channels[live[best]], share: share,
                                        fit: min(fit, 1))
        }
        return result
    }

    /// Non-negative least squares on the standardised normal equations, by
    /// coordinate descent. Non-negative because an engine can heat a sensor and not
    /// cool one: allowed to go negative, two engines that rise together take huge
    /// opposite weights and the answer means nothing.
    static func solve(gram: [[Double]], target: [Double], iterations: Int = 200) -> [Double] {
        var weights = Array(repeating: 0.0, count: target.count)
        for _ in 0..<iterations {
            for j in weights.indices {
                var residual = target[j]
                for k in weights.indices where k != j { residual -= gram[j][k] * weights[k] }
                weights[j] = max(0, residual / (gram[j][j] == 0 ? 1 : gram[j][j]))
            }
        }
        return weights
    }
}
