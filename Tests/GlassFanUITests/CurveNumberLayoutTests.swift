import Testing
import CoreGraphics
@testable import GlassFanUI

@Suite("Curve numbers")
struct CurveNumberLayoutTests {
    let range: ClosedRange<CGFloat> = 8...256

    @Test("numbers far apart stay at their lines' ends")
    func apart() {
        let placed = CurveNumberLayout.place(ends: [8, 120, 200], editing: 0, within: range)
        #expect(placed.map(\.y) == [8, 120, 200])
    }

    @Test("two curves ending together: the edited number keeps its place, the other steps down")
    func overlapping() {
        let placed = CurveNumberLayout.place(ends: [8, 8], editing: 1, within: range)
        #expect(placed[1].y == 8)
        #expect(placed[0].y == 28)
        #expect(placed[0].lineY == 8)
    }

    @Test("at the floor the other number steps up instead")
    func atFloor() {
        let placed = CurveNumberLayout.place(ends: [256, 256], editing: 0, within: range)
        #expect(placed[0].y == 256)
        #expect(placed[1].y == 236)
    }

    @Test("three together fan out, twenty points apart")
    func three() {
        let ys = CurveNumberLayout.place(ends: [8, 8, 8], editing: 2, within: range).map(\.y).sorted()
        #expect(ys == [8, 28, 48])
    }

    @Test("the edited curve is blue even when it is the one driving")
    func roles() {
        #expect(CurveRole.of(1, editing: 1, driving: 1) == .editing)
        #expect(CurveRole.of(0, editing: 1, driving: 0) == .driving)
        #expect(CurveRole.of(2, editing: 1, driving: 0) == .idle)
    }
}
