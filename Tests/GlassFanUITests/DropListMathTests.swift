import Testing
import CoreGraphics
@testable import GlassFanUI

@Suite("Drop list motion")
struct DropListMathTests {
    /// Three rows of different heights with 8 pt gaps: 0-60, 68-100, 108-140.
    let rows = [CGRect(x: 0, y: 0, width: 180, height: 60),
                CGRect(x: 0, y: 68, width: 180, height: 32),
                CGRect(x: 0, y: 108, width: 180, height: 32)]

    @Test("a row owns down to the middle of the gap on either side")
    func owner() {
        #expect(DropListMath.owner(of: 30, in: rows) == 0)
        #expect(DropListMath.owner(of: 63.9, in: rows) == 0)
        #expect(DropListMath.owner(of: 64, in: rows) == 1)
        #expect(DropListMath.owner(of: 500, in: rows) == 2)
        #expect(DropListMath.owner(of: -50, in: rows) == 0)
    }

    @Test("held, the drop hangs back near its row's middle, then gives")
    func sticks() {
        #expect(DropListMath.stick(30, in: rows) == 30)
        // Halfway from the middle (30) to the edge of row 0's stretch (64): an eighth of the way.
        #expect(abs(DropListMath.stick(47, in: rows) - 34.25) < 0.01)
        // At the edge it has caught up with the pointer.
        #expect(abs(DropListMath.stick(63.99, in: rows) - 63.99) < 0.1)
    }

    @Test("passing from one row's pull to the next, the drop does not jump")
    func continuous() {
        let before = DropListMath.stick(63.999, in: rows)
        let after = DropListMath.stick(64.001, in: rows)
        #expect(abs(before - after) < 0.05)
    }

    @Test("over a row there is no pinch; four points into a gap, full pinch")
    func gapness() {
        #expect(DropListMath.gapness(at: 30, in: rows) == 0)
        #expect(DropListMath.gapness(at: 62, in: rows) == 0.5)
        #expect(DropListMath.gapness(at: 64, in: rows) == 1)
    }

    @Test("faster is thinner and shorter, and never thinner than a seventh")
    func thinned() {
        let size = CGSize(width: 180, height: 60)
        #expect(DropListMath.thinned(size, speed: 0, gapness: 0) == size)
        let fast = DropListMath.thinned(size, speed: 2000, gapness: 1)
        #expect(abs(fast.width - 180 * 0.14) < 0.001)
        #expect(abs(fast.height - 36) < 0.001)
    }

    @Test("corners open towards a pill with speed")
    func corners() {
        #expect(DropListMath.cornerRadius(rest: 14, speed: 0) == 14)
        #expect(DropListMath.cornerRadius(rest: 14, speed: 1000) == 74)
    }
}
