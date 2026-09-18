import Testing
import Foundation
@testable import FanKit

@Suite("Configuration")
struct ConfigTests {
    @Test("round-trips through JSON")
    func roundTrip() throws {
        let cfg = AppConfig.default(fanCount: 2)
        let data = try JSONEncoder().encode(cfg)
        #expect(try JSONDecoder().decode(AppConfig.self, from: data) == cfg)
    }

    @Test("defaults give one settings block per fan, all in auto")
    func defaults() {
        let cfg = AppConfig.default(fanCount: 2)
        #expect(cfg.fans.count == 2)
        #expect(cfg.fans.allSatisfy { $0.mode == .auto })
        #expect(cfg.emergencyTemp == 95)
    }

    @Test("an emergency threshold outside a sane range is clamped on decode")
    func clampsEmergency() throws {
        let json = #"{"fans":[],"emergencyTemp":250,"pollInterval":1.0}"#
        let cfg = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(cfg.emergencyTemp == 105)
    }

    @Test("a poll interval that is too fast is clamped on decode")
    func clampsPoll() throws {
        let json = #"{"fans":[],"emergencyTemp":95,"pollInterval":0.01}"#
        let cfg = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(cfg.pollInterval == 0.25)
    }
}

@Suite("Sensor names")
struct SensorNameTests {
    @Test("shared names are told apart by key; unique ones are left alone")
    func distinct() {
        // Two keys no table names share the generated name; TB0T has its own.
        let names = SensorCatalog.distinctNames(for: ["Tzz1", "Tzz2", "TB0T"])
        #expect(names[0] != names[1])
        #expect(names[0].hasSuffix("Tzz1"))
        #expect(names[1].hasSuffix("Tzz2"))
        #expect(!names[2].contains("·"))
    }
}

/// The default chart was read off an M1 Max. On a chip that names its sensors
/// differently none of those keys exist, and the chart waited for ever.
@Suite("Charted sensors on other hardware")
struct TrackedDefaultsTests {
    @Test("where the M1 Max sensors exist they are kept, in their order")
    func keepsKnown() {
        let available = ["TB0T", "TCMz", "Tp0D", "Txxx", "TCMb"]
        #expect(SensorCatalog.trackedDefaults(available: available) == ["TCMz", "TCMb", "TB0T"])
    }

    @Test("where none exist, this machine's own sensors are charted")
    func picksFromThisMachine() {
        let available = ["Tp09", "Tp01", "Tp05", "Tg0f", "TG1d", "Ts0S", "TH0a", "TB1T"]
        let chosen = SensorCatalog.trackedDefaults(available: available)
        #expect(!chosen.isEmpty)
        #expect(chosen.allSatisfy(available.contains))
        #expect(chosen.count <= 6)
        // CPU first, and the same choice on every run.
        #expect(SensorCatalog.info(for: chosen[0]).group == .cpu)
        #expect(chosen == SensorCatalog.trackedDefaults(available: available.reversed()))
    }

    @Test("a machine with nothing readable charts nothing, rather than inventing keys")
    func nothingAvailable() {
        #expect(SensorCatalog.trackedDefaults(available: []).isEmpty)
    }

    @Test("a config written before curves were grouped comes through as curve one")
    func migratesSingleCurve() throws {
        let json = #"""
        {"id":0,"mode":"curve","fixedRPM":2000,"sensorKeys":["Ts0P","Ts1P"],
         "curve":[{"temperature":40,"rpm":0},{"temperature":80,"rpm":3000}],
         "hysteresis":2,"smoothing":0.3}
        """#
        let settings = try JSONDecoder().decode(FanSettings.self, from: Data(json.utf8))
        #expect(settings.curves.count == 1)
        #expect(settings.curves[0].sensorKeys == ["Ts0P", "Ts1P"])
        #expect(settings.curves[0].curve.points.count == 2)
    }

    @Test("curve one is written in the old shape too, for a daemon that predates groups")
    func writesBothShapes() throws {
        let settings = FanSettings(id: 0, mode: .curve, fixedRPM: 2000, curves: [
            CurveRule(sensorKeys: ["Ts0P"], curve: .starter(maxRPM: 5000)),
            CurveRule(sensorKeys: ["TCMz"], curve: .starter(maxRPM: 5000)),
        ], hysteresis: 2, smoothing: 0.3)
        let data = try JSONEncoder().encode(settings)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["sensorKeys"] as? [String] == ["Ts0P"])
        #expect((object["curve"] as? [Any])?.count == 2)
        #expect((object["curves"] as? [Any])?.count == 2)
        #expect(try JSONDecoder().decode(FanSettings.self, from: data) == settings)
    }

    @Test("no more than three curves, and never none")
    func curveCount() {
        let rule = CurveRule(curve: .starter(maxRPM: 5000))
        let many = FanSettings(id: 0, mode: .curve, fixedRPM: 2000, curves: Array(repeating: rule, count: 5),
                               hysteresis: 2, smoothing: 0)
        #expect(many.curves.count == FanSettings.maxCurves)
        let none = FanSettings(id: 0, mode: .curve, fixedRPM: 2000, curves: [], hysteresis: 2, smoothing: 0)
        #expect(none.curves.count == 1)
    }

    @Test("a sensor in two groups is listed once")
    func allSensorKeys() {
        let settings = FanSettings(id: 0, mode: .curve, fixedRPM: 2000, curves: [
            CurveRule(sensorKeys: ["A", "B"], curve: .starter(maxRPM: 5000)),
            CurveRule(sensorKeys: ["B", "C"], curve: .starter(maxRPM: 5000)),
        ], hysteresis: 2, smoothing: 0)
        #expect(settings.allSensorKeys == ["A", "B", "C"])
    }
}
