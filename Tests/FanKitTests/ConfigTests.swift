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
        let names = SensorCatalog.distinctNames(for: ["Tp0D", "Tp0E", "TG0B"])
        #expect(names[0] != names[1])
        #expect(names[0].hasSuffix("Tp0D"))
        #expect(names[1].hasSuffix("Tp0E"))
        #expect(!names[2].contains("·"))
    }
}
