import SwiftUI

// The glass drop, as every control that has one draws it: the segmented control's
// capsule and the drop list's drawn-out drop are one shape to the shader, lit and
// refracted by the same code, and moved by the same springs.

/// A damped spring for one number, stepped by hand.
///
/// The lens's position, width, lift and stretch each have one. They were SwiftUI
/// animations first, and SwiftUI animates a view's animatable values together,
/// under whichever animation last touched any of them: the glide took on the
/// stretch's bounce and overshot, and every new animation restarted the others.
struct LensSpring {
    var value: CGFloat = 0
    var velocity: CGFloat = 0
    var target: CGFloat = 0
    private var stiffness: CGFloat = 400
    private var damping: CGFloat = 40

    /// In SwiftUI's own terms: `response` is the period of the undamped motion, and
    /// a `dampingFraction` of 1 arrives without overshooting.
    mutating func tune(response: CGFloat, dampingFraction: CGFloat) {
        let omega = 2 * .pi / max(response, 0.01)
        stiffness = omega * omega
        damping = 2 * dampingFraction * omega
    }

    mutating func jump(to newValue: CGFloat) {
        value = newValue
        target = newValue
        velocity = 0
    }

    mutating func step(_ dt: CGFloat) {
        velocity += (-stiffness * (value - target) - damping * velocity) * dt
        value += velocity * dt
    }

    func isResting(within tolerance: CGFloat) -> Bool {
        abs(value - target) < tolerance && abs(velocity) < tolerance * 20
    }
}

/// Runs `change` with implicit animations off.
///
/// The resting platter slides between choices by an implicit animation keyed on the
/// choice, so a choice made from the keyboard or the menu bar glides. A drop makes
/// its choice while in the air and then settles into the platter where it landed;
/// with that animation still armed, the platter came back at the old choice and slid
/// over a moment after the drop had visibly settled. The drop's own choice and its
/// settling are made with implicit animations off.
func withoutImplicitAnimation(_ change: () -> Void) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction, change)
}

/// Hands out one step of time per display frame, however many views ask for it.
///
/// A drop is drawn by three views - the glass under the content, the refraction, the
/// light over it - and each asks for the frame it is drawing. Their timelines hand
/// them times up to 3 ms apart within one frame; stepped to each, the three parts
/// were drawn a point or two apart, by a different amount every frame, and a fast drop
/// shimmered. The first to ask in a frame steps the springs; the others, arriving
/// within a few milliseconds, get the same drop.
struct FrameClock {
    private var steppedTo: TimeInterval = 0
    private var askedAt: TimeInterval = -1

    mutating func reset() { steppedTo = 0 }

    /// Sub-steps to advance by, or nil when this frame has been stepped already.
    /// `now` is the process's uptime; tests pass their own.
    mutating func advance(to time: TimeInterval,
                          now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> (count: Int, dt: CGFloat)? {
        guard now - askedAt > 0.004 else { return nil }
        askedAt = now
        guard time > steppedTo else { return nil }
        // After a stall - a screen being built - the drop carries on from where it
        // was, rather than leaping to where it would have got to.
        let elapsed = steppedTo == 0 ? 0 : min(time - steppedTo, 1.0 / 30)
        steppedTo = time
        guard elapsed > 0 else { return nil }
        let count = Int((elapsed * 480).rounded(.up))
        return (count, CGFloat(elapsed) / CGFloat(count))
    }
}

/// Where a drop of glass is and how far it has lifted: a head and a tail, each a
/// rounded box, joined by a bridge. The segmented control's drop is a capsule - one
/// box, round-ended; the list's is drawn out between two rows.
struct DropGeometry: Equatable {
    var head: CGRect
    var tail: CGRect
    var cornerRadius: CGFloat
    /// Radius of the bridge between head and tail; 0 for none.
    var neck: CGFloat = 0
    /// 0 for a platter at rest, 1 for the drop fully up.
    var lift: CGFloat
    /// Speed along the way it moves, -1...1: the light swings and the colours part with it.
    var motion: CGFloat = 0
    var maxMagnification: CGFloat = 1.1

    static func capsule(_ rect: CGRect, lift: CGFloat, motion: CGFloat) -> DropGeometry {
        DropGeometry(head: rect, tail: rect, cornerRadius: rect.height / 2, lift: lift, motion: motion)
    }

    var bounds: CGRect { head.union(tail) }
    var magnification: CGFloat { 1 + (maxMagnification - 1) * min(lift, 1) }
    var isVisible: Bool { lift > 0.002 }

    /// The same drop with both ends drawn in by `inset` on every side.
    func insetBy(_ inset: CGFloat) -> DropGeometry {
        var smaller = self
        smaller.head = head.insetBy(dx: inset, dy: inset)
        smaller.tail = tail.insetBy(dx: inset, dy: inset)
        smaller.cornerRadius = max(cornerRadius - inset, 2)
        return smaller
    }

    func offsetBy(dx: CGFloat, dy: CGFloat) -> DropGeometry {
        var moved = self
        moved.head = head.offsetBy(dx: dx, dy: dy)
        moved.tail = tail.offsetBy(dx: dx, dy: dy)
        return moved
    }

    /// The shape for glass and shadow behind the shader's drop: its boxes and bridge,
    /// joined. The shader melts the joins; at these sizes a sharp join under a soft
    /// rim cannot be told from it.
    var outline: Path {
        func box(_ rect: CGRect) -> Path {
            Path(roundedRect: rect, cornerRadius: min(cornerRadius, rect.width / 2, rect.height / 2),
                 style: .continuous)
        }
        guard tail != head else { return box(head) }
        var shape = box(head).union(box(tail))
        if neck > 0 {
            let bridge = Path { path in
                path.move(to: CGPoint(x: head.midX, y: head.midY))
                path.addLine(to: CGPoint(x: tail.midX, y: tail.midY))
            }.strokedPath(StrokeStyle(lineWidth: neck * 2, lineCap: .round))
            shape = shape.union(bridge)
        }
        return shape
    }

    /// The shape as the shaders take it: head, tail, corner radius, neck.
    fileprivate var shaderShape: [Shader.Argument] {
        [.float4(head.minX, head.minY, head.width, head.height),
         .float4(tail.minX, tail.minY, tail.width, tail.height),
         .float(cornerRadius),
         .float(neck)]
    }
}

struct DropOutline: Shape {
    let geometry: DropGeometry
    /// With the bridge between the ends, or the ends alone.
    var bridged = true

    func path(in rect: CGRect) -> Path {
        if bridged { return geometry.outline }
        var ends = geometry
        ends.neck = 0
        return ends.outline
    }
}

/// Refracts what is under the drop, on the GPU. Off whenever the drop is down: a
/// layer effect renders the view offscreen, and a resting control has no business
/// paying for that.
struct GlassDropRefraction: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let geometry: DropGeometry?
    /// How far the shader may reach for what it shows. By default worked out from the
    /// drop each frame; a control whose drop is large gives a fixed one, because a
    /// reach that changes as the effect switches off came out as one frame of the
    /// content drawn out of place.
    var reach: CGSize? = nil

    /// Room around the content for the parts of the drop that reach past it: it
    /// stands taller than the row it sits on, and draws out when it moves.
    private let room: CGFloat = 16

    func body(content: Content) -> some View {
        if let library = LensShaders.library {
            let geometry = (geometry ?? DropGeometry(head: .zero, tail: .zero, cornerRadius: 0, lift: 0))
                .offsetBy(dx: room, dy: room)
            let bounds = geometry.bounds
            let thick = min(geometry.head.width, geometry.head.height, geometry.tail.width, geometry.tail.height)
            content
                .padding(room)
                .layerEffect(
                    Shader(function: ShaderFunction(library: library, name: "glassLens"),
                           arguments: geometry.shaderShape + [
                               .float(geometry.magnification),
                               .float(min(geometry.lift, 1)),
                               .float(geometry.motion),
                               // The ink follows the scheme: dark labels in light mode.
                               .float(colorScheme == .light ? 1 : 0),
                           ] + LensTuning.shared.lensArguments),
                    // How far the drop reaches for what it shows: the magnified body,
                    // the bend of the rim, and the reflection beside it.
                    maxSampleOffset: reach ?? CGSize(width: bounds.width * 0.3 + thick + 8,
                                                     height: bounds.height * 0.3 + thick + 8),
                    isEnabled: geometry.isVisible
                )
                .padding(-room)
        } else {
            content
        }
    }
}

/// The edge of the drop: the one thing its glass does not draw itself.
///
/// A colour effect of its own, over the refracted content rather than part of it -
/// SwiftUI composites a layer effect's translucent output twice over a band of the
/// layer wherever it may sample far afield, and a translucent edge came out as a
/// stripe across the drop.
struct GlassDropLight: View {
    @Environment(\.colorScheme) private var colorScheme
    let geometry: DropGeometry
    /// Where the pointer is, in the same coordinates as `geometry`. Kept for callers
    /// that still hand it over; the glass no longer blooms under it.
    var pointer: CGPoint = .zero
    /// The area the drop moves over, in the same coordinates as `geometry`.
    let size: CGSize

    /// Room around the area for what reaches past it.
    private let margin: CGFloat = 16

    var body: some View {
        if geometry.isVisible, let library = LensShaders.library, !DropScript.off.contains("shader") {
            let drop = geometry.offsetBy(dx: margin, dy: margin)
            Rectangle()
                .fill(.white)
                .colorEffect(Shader(function: ShaderFunction(library: library, name: "glassLight"),
                                    arguments: drop.shaderShape + [
                                        .float(min(drop.lift, 1)),
                                        .float(drop.motion),
                                        .float(colorScheme == .light ? 1 : 0),
                                    ] + LensTuning.shared.lightArguments))
                .frame(width: size.width + margin * 2, height: size.height + margin * 2)
                .offset(x: -margin, y: -margin)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

enum LensShaders {
    /// The compiled lens shader, or nil if the app was put together without it -
    /// then the lens still lifts and glides, only without magnifying.
    static let library: ShaderLibrary? = {
        let name = "GlassFan_GlassFanUI.bundle"
        let token = Bundle(for: LensState.self)
        let places = [Bundle.main.resourceURL, Bundle.main.bundleURL, token.resourceURL,
                      token.bundleURL.deletingLastPathComponent()]
        for place in places.compactMap({ $0 }) {
            if let bundle = Bundle(url: place.appendingPathComponent(name)),
               let url = bundle.url(forResource: "default", withExtension: "metallib") {
                return ShaderLibrary(url: url)
            }
        }
        // Xcode previews lay the package out their own way; SwiftPM's accessor
        // knows it. Not used elsewhere, because it traps when the bundle is missing.
        return Runtime.isPreview ? ShaderLibrary.bundle(.module) : nil
    }()
}

#if DEBUG
/// The light over a drop of known size, that size outlined in red: they must agree.
///
/// Head and tail a point and a half apart, as they are the moment a drop is pressed.
/// The shader's melt between them once swelled the whole drop ten points past this
/// outline - the ring of light around a row it should have sat on.
#Preview("Drop light alignment") {
    let head = CGRect(x: 0, y: 0, width: 184, height: 96)
    let tail = head.offsetBy(dx: 0, dy: 1.5)
    ZStack(alignment: .topLeading) {
        Color(red: 0.12, green: 0.14, blue: 0.19).frame(width: 184, height: 200)
        RoundedRectangle(cornerRadius: 14).stroke(.red, lineWidth: 1)
            .frame(width: head.width, height: head.height + 1.5)
    }
    .overlay(alignment: .topLeading) {
        GlassDropLight(geometry: DropGeometry(head: head, tail: tail, cornerRadius: 14, lift: 1),
                       pointer: CGPoint(x: head.midX, y: head.midY), size: CGSize(width: 184, height: 200))
    }
    .padding(30)
    .background(Color(red: 0.12, green: 0.14, blue: 0.19))
    .environment(\.colorScheme, .dark)
}
#endif
