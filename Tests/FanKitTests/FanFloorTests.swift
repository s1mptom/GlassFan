import Testing
import Foundation
@testable import FanKit

/// Learning how slowly a fan will actually turn, from readings the daemon takes anyway.
///
/// The shapes here are the ones that would otherwise produce a wrong answer: a fan
/// coasting down past every speed there is, a fan doing exactly what it was told, and
/// a fan the system rather than this daemon is driving.
@Suite("Fan floor")
struct FanFloorTests {
    private func settle(_ floor: inout FanFloor, target: Double, actual: Double,
                        seconds: Int = FanFloor.steadySeconds) {
        for _ in 0..<seconds { floor.observe(target: target, actual: actual, held: true) }
    }

    @Test("a fan asked for less than it will do says what it will do")
    func learnsFromRefusal() {
        var floor = FanFloor()
        // The reading that started this: 446 asked for, 968 delivered.
        for _ in 0..<FanFloor.episodesNeeded {
            settle(&floor, target: 446, actual: 968)
            floor.observe(target: 2000, actual: 2000, held: true)   // ends the episode
        }
        #expect(floor.isKnown)
        #expect(floor.learned == 968)
        #expect(floor.episodes == FanFloor.episodesNeeded)
    }

    @Test("one settled stretch is not an answer")
    func oneEpisodeIsNotEnough() {
        var floor = FanFloor()
        settle(&floor, target: 446, actual: 968)
        #expect(floor.learned == 968)      // seen
        #expect(!floor.isKnown)            // not yet believed
    }

    @Test("a fan on its way down is not at its floor")
    func coastingIsNotSettling() {
        var floor = FanFloor()
        // 5000 rpm to a stop passes through every speed there is, and each one looks
        // like a floor for a second.
        for rpm in stride(from: 5000.0, to: 900, by: -200) {
            floor.observe(target: 400, actual: rpm, held: true)
        }
        #expect(floor.learned == nil)
    }

    @Test("a fan doing what it was told teaches nothing about how low it goes")
    func obedienceIsNotEvidence() {
        var floor = FanFloor()
        for _ in 0..<FanFloor.episodesNeeded {
            settle(&floor, target: 2000, actual: 2010)
            floor.observe(target: 3000, actual: 3000, held: true)
        }
        #expect(floor.learned == nil)
        #expect(!floor.isKnown)
    }

    @Test("readings from a fan the system is driving are not evidence")
    func onlyWhatWeHoldCounts() {
        var floor = FanFloor()
        for _ in 0..<40 { floor.observe(target: 0, actual: 968, held: false) }
        #expect(floor.learned == nil)
    }

    @Test("a stopped fan is a stopped fan, not a floor of zero")
    func stoppedIsNotAFloor() {
        var floor = FanFloor()
        for _ in 0..<40 { floor.observe(target: 0, actual: 0, held: true) }
        #expect(floor.learned == nil)
    }

    @Test("the lowest refusal wins, and a later higher one does not raise it")
    func keepsTheLowest() {
        var floor = FanFloor()
        settle(&floor, target: 400, actual: 1100)
        floor.observe(target: 2000, actual: 2000, held: true)
        settle(&floor, target: 400, actual: 968)
        floor.observe(target: 2000, actual: 2000, held: true)
        settle(&floor, target: 400, actual: 1050)
        #expect(floor.learned == 968)
    }

    @Test("a wandering reading is not settled, however long it goes on")
    func wanderingNeverSettles() {
        var floor = FanFloor()
        for i in 0..<60 {
            floor.observe(target: 400, actual: i % 2 == 0 ? 900 : 1400, held: true)
        }
        #expect(floor.learned == nil)
    }

    @Test("what is learned survives the round trip to disk")
    func isCodable() throws {
        var floor = FanFloor()
        for _ in 0..<FanFloor.episodesNeeded {
            settle(&floor, target: 446, actual: 968)
            floor.observe(target: 2000, actual: 2000, held: true)
        }
        let data = try JSONEncoder().encode(floor)
        let back = try JSONDecoder().decode(FanFloor.self, from: data)
        #expect(back.learned == floor.learned)
        #expect(back.isKnown)
    }
}
