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

    @Test("held, the drop stays on its row and leans a quarter of the way to the pointer")
    func sticks() {
        #expect(DropListMath.stick(30, in: rows) == 30)
        #expect(DropListMath.stick(47, in: rows) == 34.25)
        #expect(DropListMath.stick(63.9, in: rows) < 40)       // never out over the gap
    }

    @Test("past the middle of a gap the drop belongs to the next row")
    func handedOver() {
        #expect(DropListMath.stick(64, in: rows) == 79)        // row 2's middle (84), leaning up
        #expect(DropListMath.stick(500, in: rows) > 124)       // the last row, leaning down
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
