import Testing
import Foundation
import CoreGraphics
@testable import GlassFanUI

/// The drop's springs run frame by frame here, on a clock of the test's own, so what
/// it does in flight can be checked without anything on screen.
@MainActor
@Suite("Drop list flight")
struct DropListStateTests {
    let rows = [CGRect(x: 0, y: 0, width: 180, height: 60),
                CGRect(x: 0, y: 68, width: 180, height: 32),
                CGRect(x: 0, y: 108, width: 180, height: 32)]

    /// Runs `seconds` of frames at 60 a second, handing each frame's drop to `each`.
    func fly(_ drop: DropListState, seconds: Double, each: (DropGeometry) -> Void = { _ in }) {
        let start = 1000.0
        for frame in 0...Int(seconds * 60) {
            let t = start + Double(frame) / 60
            each(drop.geometry(at: Date(timeIntervalSinceReferenceDate: t), rows: rows, now: t))
        }
    }

    @Test("sent to another row, the drop thins and draws out on the way, and arrives whole")
    func flight() {
        let drop = DropListState()
        drop.engage(at: rows[0])
        drop.lift.target = 1
        drop.target = 2
        var narrowest = CGFloat.infinity, longest: CGFloat = 0
        fly(drop, seconds: 1.5) { g in
            narrowest = min(narrowest, g.head.width)
            longest = max(longest, abs(g.head.midY - g.tail.midY))
        }
        #expect(narrowest < 180 * 0.5)          // it thinned in flight
        #expect(longest > 10)                   // the tail lagged: it drew out
        #expect(abs(drop.headY.value - rows[2].midY) < 1.5)
        #expect(abs(drop.tailY.value - rows[2].midY) < 1.5)
        #expect(abs(drop.headW.value - 180) < 1.5)
        #expect(abs(drop.headH.value - 32) < 1.5)
    }

    @Test("held inside its row's stretch, the drop stays on the row, leaning towards the pointer")
    func sticksWhileHeld() {
        let drop = DropListState()
        drop.engage(at: rows[0])
        drop.held = 47
        fly(drop, seconds: 1.5)
        #expect(abs(drop.headY.value - 34.25) < 1)
    }
}
