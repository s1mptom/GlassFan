import Testing
import SwiftUI
@testable import GlassFanUI

@Suite("Drop geometry")
struct DropGeometryTests {
    @Test("a capsule is one box with a radius of half its height")
    func capsule() {
        let rect = CGRect(x: 10, y: 4, width: 96, height: 30)
        let drop = DropGeometry.capsule(rect, lift: 1, motion: 0)
        #expect(drop.head == rect && drop.tail == rect)
        #expect(drop.cornerRadius == 15)
        #expect(drop.neck == 0)
        #expect(drop.bounds == rect)
    }

    @Test("the outline covers head, tail and the bridge between them")
    func outline() {
        let drop = DropGeometry(head: CGRect(x: 0, y: 0, width: 100, height: 40),
                                tail: CGRect(x: 0, y: 80, width: 100, height: 40),
                                cornerRadius: 14, neck: 10, lift: 1)
        let path = drop.outline
        #expect(path.contains(CGPoint(x: 50, y: 20)))
        #expect(path.contains(CGPoint(x: 50, y: 100)))
        #expect(path.contains(CGPoint(x: 50, y: 60)))   // the neck
        #expect(!path.contains(CGPoint(x: 5, y: 60)))   // beside the neck, in the gap
    }

    @Test("the frame clock steps each frame once, and no more than a thirtieth of a second")
    func frameClock() {
        var clock = FrameClock()
        #expect(clock.advance(to: 10, now: 0.5) == nil)   // the first call only starts it
        let step = clock.advance(to: 10.5, now: 1)!
        #expect(abs(CGFloat(step.count) * step.dt - 1.0 / 30) < 1e-6)
        #expect(clock.advance(to: 10.6, now: 1.001) == nil)   // same frame: another view asking
    }
}
