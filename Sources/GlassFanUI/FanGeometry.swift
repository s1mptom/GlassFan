import CoreGraphics
import Foundation

/// The GlassFan blade and the wake behind it - one formula for the dial in the
/// app and for the app icon.
///
/// Designed on the icon canvas as direction A ("six swept"): six crescent blades,
/// tips swept back against the spin. The numbers here are the contract;
/// `Scripts/make-icon.swift` carries a copy of them and
/// `design/glassfan-icon/fan_geometry.py` is where they were drawn.
///
/// Units: radius 1 at the tips, centre at the origin, y pointing down, angle 0
/// straight up and positive angles clockwise on screen - the way the disc spins.
enum FanGeometry {
    static let count = 6
    /// Where the blade leaves the hub, as a share of the tip radius.
    static let root = 0.24
    /// How far the tip lags the root, in radians. Negative: counter-clockwise,
    /// against the spin, so the blade leans back the way its wake trails.
    static let sweep = -0.62
    static let sweepPower = 1.5
    /// Half the blade's width, as arc length at the tip radius.
    static let width = 0.18
    /// Below 1 the tip is rounded rather than pointed.
    static let tipBluntness = 0.32
    /// Width at the root as a share of the widest part.
    static let rootFraction = 0.45
    static let hub = 0.27
    /// The set is turned so a blade's mid-length sits on the vertical axis -
    /// what makes a swept star read as balanced.
    static let orientation = -sweep * 0.55

    /// One blade: the trailing edge from root to tip, then the leading edge back.
    static func outline(samples: Int = 26) -> [CGPoint] {
        var lead: [CGPoint] = [], trail: [CGPoint] = []
        for i in 0...samples {
            let u = Double(i) / Double(samples)
            let t = 1 - (1 - u) * (1 - u)                     // denser towards the tip
            let r = root + t * (1 - root)
            let phi = sweep * pow(t, sweepPower)
            let half = width * pow(1 - t, tipBluntness)
                * (rootFraction + (1 - rootFraction) * 1.35 * t)
            let dth = half / max(r, 1e-6)
            lead.append(point(r, phi + dth))
            trail.append(point(r, phi - dth))
        }
        return trail + lead.reversed().dropFirst()
    }

    private static func point(_ r: Double, _ theta: Double) -> CGPoint {
        CGPoint(x: r * sin(theta), y: -r * cos(theta))
    }

    /// Every blade and the hub, as one path: tips at `radius` around `centre`,
    /// in a y-down space. The outline is smoothed Catmull-Rom; the straight
    /// closing edge at the root sits under the hub.
    static func path(centre: CGPoint, radius: CGFloat, includesHub: Bool = true) -> CGPath {
        let blade = CGMutablePath()
        let pts = outline()
        blade.move(to: pts[0])
        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(i - 1, 0)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(i + 2, pts.count - 1)]
            blade.addCurve(to: p2,
                           control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                           control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        blade.closeSubpath()

        let all = CGMutablePath()
        for i in 0..<count {
            let turn = CGAffineTransform(translationX: centre.x, y: centre.y)
                .scaledBy(x: radius, y: radius)
                .rotated(by: orientation + Double(i) * 2 * .pi / Double(count))
            all.addPath(blade, transform: turn)
        }
        if includesHub {
            let r = radius * hub
            all.addEllipse(in: CGRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r))
        }
        return all
    }

    /// The wake: copies of the blades turned back against the spin, fading.
    ///
    /// Behind the blade only. The air used to be an angular gradient with a lobe
    /// centred between blades, so it sat on both sides of each one; this is what
    /// a camera sees of anything spinning, and it lies wholly on the trailing
    /// side. Angles are in radians, negative - counter-clockwise, since the disc
    /// turns clockwise. `spread` is how far towards full speed, 0 to 1: nothing
    /// at rest, longer and stronger as the fan speeds up.
    static func wake(spread: Double, ghosts: Int = 16) -> [(angle: Double, opacity: Double)] {
        let s = min(max(spread, 0), 1)
        guard s > 0, ghosts > 1 else { return [] }
        let strength = 0.9 * min(s * 1.6, 1)
        let span = (0.3 + 0.55 * s) * 2 * .pi / Double(count)
        return (1..<ghosts).map { k in
            let f = Double(k) / Double(ghosts)
            return (angle: -f * span, opacity: strength * pow(1 - f, 1.6))
        }
    }
}
