import Foundation
import FanKit

/// Fixed readings matching the design mockup, so the built app can be compared against
/// it one for one. Screenshot fixture only - switched on with MACFANS_DEMO=1 and never
/// reachable otherwise.
enum DemoFixture {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["MACFANS_DEMO"] == "1"
    }

    static let limits0 = FanLimits(minRPM: 1499, maxRPM: 5348)
    static let limits1 = FanLimits(minRPM: 1499, maxRPM: 5776)

    static let temperatures: [(String, Double)] = [
        ("TCMz", 78.5), ("Tp0D", 69.1), ("TaRT", 37.0), ("TG0B", 34.3),
        ("Ts0P", 33.0), ("Ts1P", 31.0), ("TH0b", 34.0), ("TB0T", 31.2),
        ("Te02", 63.2), ("Tp0E", 64.5),
    ]

    static func snapshot() -> Snapshot {
        var config = AppConfig.default(fanCount: 2)
        config.fans[0].mode = .curve
        config.fans[0].sensorKeys = ["TCMz", "TaRT"]
        config.fans[0].curve = .defaultCurve(minRPM: limits0.minRPM, maxRPM: limits0.maxRPM)
        config.trackedSensors = ["TCMz", "Tp0D", "TaRT", "TG0B"]

        return Snapshot(
            time: Date().timeIntervalSince1970,
            sensors: temperatures.map { SensorReading(key: $0.0, value: $0.1) },
            fans: [
                FanReading(index: 0, actualRPM: 2600, targetRPM: 2600, limits: limits0,
                           mode: .curve, forced: true, drivingTemp: 78.5, emergency: false),
                FanReading(index: 1, actualRPM: 1654, targetRPM: 1654, limits: limits1,
                           mode: .auto, forced: false, drivingTemp: nil, emergency: false),
            ],
            config: config,
            daemonVersion: "demo"
        )
    }

    /// Fifteen minutes of plausible wander, so the chart has the same shape every run.
    static func history() -> [HistorySample] {
        let now = Date().timeIntervalSince1970
        let keys = ["TCMz", "Tp0D", "TaRT", "TG0B"]
        let bases: [Double] = [76, 67, 37, 34]
        return (0..<900).map { step in
            let t = Double(step)
            var temps: [String: Double] = [:]
            for (index, key) in keys.enumerated() {
                let slow = sin(t / 130 + Double(index)) * (index < 2 ? 3.5 : 0.6)
                let fast = sin(t / 11 + Double(index) * 2) * (index < 2 ? 1.8 : 0.2)
                temps[key] = bases[index] + slow + fast
            }
            return HistorySample(t: now - 900 + t, temps: temps,
                                 fanRPM: [2600 + sin(t / 90) * 120, 1654 + sin(t / 70) * 60])
        }
    }
}
