import Testing
import Foundation
import CoreGraphics
@testable import GlassFanUI

/// The wake was reported sitting on both sides of each blade. It is copies of
/// the blades turned back against the spin; these pin that they are only ever
/// turned back, and that the blade itself is the shape the icon was drawn with.
@Suite("Fan geometry")
struct FanGeometryTests {

    @Test("the wake lies behind the blade only, and fades with distance")
    func wakeTrails() {
        let ghosts = FanGeometry.wake(spread: 0.6)
        #expect(!ghosts.isEmpty)
        // The disc turns clockwise, so behind is counter-clockwise: negative.
        #expect(ghosts.allSatisfy { $0.angle < 0 })
        for (near, far) in zip(ghosts, ghosts.dropFirst()) {
            #expect(far.angle < near.angle)
            #expect(far.opacity < near.opacity)
        }
        // Never reaching the blade in front.
        #expect(ghosts.map(\.angle).min()! > -2 * .pi / Double(FanGeometry.count))
    }

    @Test("a stopped fan has no wake, and a faster one a longer one")
    func wakeFollowsSpeed() {
        #expect(FanGeometry.wake(spread: 0).isEmpty)
        let slow = FanGeometry.wake(spread: 0.2).map(\.angle).min()!
        let fast = FanGeometry.wake(spread: 1).map(\.angle).min()!
        #expect(fast < slow)
    }

    @Test("the blade runs from under the hub to the tip, swept back against the spin")
    func bladeShape() {
        let pts = FanGeometry.outline()
        let radii = pts.map { hypot($0.x, $0.y) }
        #expect(abs(radii.max()! - 1) < 0.01)
        #expect(radii.min()! < FanGeometry.hub)
        // The tip is counter-clockwise of the root: with angle 0 up and clockwise
        // positive, its angle is the smaller one.
        let tip = pts[radii.firstIndex(of: radii.max()!)!]
        let root = pts[0]
        #expect(atan2(Double(tip.x), -Double(tip.y)) < atan2(Double(root.x), -Double(root.y)))
    }
}
