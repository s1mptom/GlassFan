import Testing
import Foundation
@testable import MacFansUI

/// The dial's rotation was `timeIntervalSinceReferenceDate * rate`, and because
/// that elapsed time is enormous, every change of rate rewrote the whole product
/// and threw the blades to a new random angle. One reading a second meant one
/// visible jerk a second.
///
/// These pin the property that broke: the angle is a running total, so a change
/// of rate may only change what happens next.
@MainActor
@Suite("Blade rotation")
struct BladeSpinTests {
    private static let frame = 1.0 / 60

    /// Steps `spin` forward `frames` frames at `rate`, returning the final angle.
    private func run(_ spin: BladeSpin, from start: Date, frames: Int, rate: Double) -> Double {
        var angle = spin.angle
        for step in 1...frames {
            angle = spin.advance(to: start.addingTimeInterval(Double(step) * Self.frame),
                                 rate: rate)
        }
        return angle
    }

    @Test("a second at a steady rate turns by that many degrees")
    func steadyRate() {
        let start = Date(timeIntervalSinceReferenceDate: 810_914_597.431)
        let spin = BladeSpin()
        _ = spin.advance(to: start, rate: 130)
        let angle = run(spin, from: start, frames: 60, rate: 130)
        #expect(abs(angle - 130) < 0.5)
    }

    /// The regression. A rate that changes between frames may move the blades by
    /// one frame's worth and no more, whatever the wall clock happens to read.
    @Test("changing the rate does not move the blades")
    func rateChangeDoesNotJump() {
        let start = Date(timeIntervalSinceReferenceDate: 810_914_597.431)
        let spin = BladeSpin()
        _ = spin.advance(to: start, rate: 130)
        let before = run(spin, from: start, frames: 60, rate: 130)

        // The old code threw the blades ~10 degrees for a single rpm and ~99 for
        // ten. One frame at these rates is about 2.2 degrees.
        let after = spin.advance(to: start.addingTimeInterval(61 * Self.frame), rate: 130.5)
        #expect(abs(after - before) < 3)
    }

    @Test("the angle stays bounded rather than growing without limit")
    func angleWraps() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let spin = BladeSpin()
        _ = spin.advance(to: start, rate: 300)
        let angle = run(spin, from: start, frames: 60 * 60, rate: 300)
        #expect(abs(angle) < 360)
    }

    /// A window that was hidden, or a machine that slept, hands back a gap of
    /// seconds. Spinning through all of it at once is the glitch this avoids.
    @Test("a long gap advances by at most one frame")
    func longGapIsClamped() {
        let start = Date(timeIntervalSinceReferenceDate: 100)
        let spin = BladeSpin()
        _ = spin.advance(to: start, rate: 300)
        let angle = spin.advance(to: start.addingTimeInterval(45), rate: 300)
        #expect(angle <= 300 / 20 + 0.001)
    }

    @Test("a stopped fan does not drift")
    func stoppedFanHolds() {
        let start = Date(timeIntervalSinceReferenceDate: 100)
        let spin = BladeSpin()
        _ = spin.advance(to: start, rate: 0)
        let angle = run(spin, from: start, frames: 120, rate: 0)
        #expect(angle == 0)
    }
}
