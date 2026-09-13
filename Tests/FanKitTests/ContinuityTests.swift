import Testing
import Foundation
@testable import FanKit

@Suite("History across restarts")
struct HistoryRecordTests {
    private func sample(_ t: Double) -> HistorySample {
        HistorySample(t: t, temps: ["TCMz": 70.123456789], fanRPM: [2600.4])
    }

    @Test("a restore keeps the last half hour, in order, and nothing from the future")
    func restorable() {
        let now = 10_000.0
        let saved = [sample(now - 3000), sample(now - 100), sample(now - 1799), sample(now + 3600), sample(now - 5)]
        let kept = HistoryRecord.restorable(saved, now: now, capacity: 1800)
        #expect(kept.map(\.t) == [now - 1799, now - 100, now - 5])
    }

    @Test("a restore holds no more than the history does")
    func capped() {
        let now = 10_000.0
        let saved = (0..<50).map { sample(now - Double($0)) }
        let kept = HistoryRecord.restorable(saved, now: now, capacity: 10)
        #expect(kept.count == 10)
        #expect(kept.last?.t == now)
    }

    @Test("saved values are rounded to what can be seen")
    func compacted() {
        let c = HistoryRecord.compacted([sample(1.23456)])[0]
        #expect(c.temps["TCMz"] == 70.12)
        #expect(c.fanRPM == [2600])
        #expect(c.t == 1.23)
    }
}

/// Every wake from sleep was logged as the control loop hanging for the length
/// of the sleep. These pin the distinction.
@Suite("Watchdog: sleep is not a stall")
struct LoopHealthTests {
    @Test("a long wall-clock gap with no awake time is a sleep")
    func sleep() {
        #expect(LoopHealth.classify(wallAge: 3649, awakeAge: 2, limit: 10) == .slept(3647))
    }

    @Test("a gap of awake time is a real stall")
    func stall() {
        #expect(LoopHealth.classify(wallAge: 40, awakeAge: 40, limit: 10) == .stalled(40))
    }

    @Test("within the limit the loop is fine")
    func ticking() {
        #expect(LoopHealth.classify(wallAge: 3, awakeAge: 3, limit: 10) == .ticking)
    }
}
