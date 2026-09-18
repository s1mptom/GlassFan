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
    var maxMagnification: CGFloat = 1.3

    static func capsule(_ rect: CGRect, lift: CGFloat, motion: CGFloat) -> DropGeometry {
        DropGeometry(head: rect, tail: rect, cornerRadius: rect.height / 2, lift: lift, motion: motion)
    }

    var bounds: CGRect { head.union(tail) }
    var magnification: CGFloat { 1 + (maxMagnification - 1) * min(lift, 1) }
    var isVisible: Bool { lift > 0.002 }

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
    func path(in rect: CGRect) -> Path { geometry.outline }
}

/// Refracts what is under the drop, on the GPU. Off whenever the drop is down: a
/// layer effect renders the view offscreen, and a resting control has no business
/// paying for that.
struct GlassDropRefraction: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let geometry: DropGeometry?

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
                           ]),
                    // How far the drop reaches for what it shows: the magnified body,
                    // the bend of the rim, and the reflection beside it.
                    maxSampleOffset: CGSize(width: bounds.width * 0.3 + thick + 8,
                                            height: bounds.height * 0.3 + thick + 8),
                    isEnabled: geometry.isVisible
                )
                .padding(-room)
        } else {
            content
        }
    }
}

/// The light on the drop and what it casts: the glare, edge and shading worked out
/// from its shape by a shader, its shadow on what is below, and the bloom under the
/// pointer.
///
/// Painted in one `Canvas` rather than built from views: as a shadow, masks and a
/// dozen strokes, the lens was rebuilt as a view tree on every frame, and that, not
/// the drawing, was what moving it cost.
struct GlassDropLight: View {
    @Environment(\.colorScheme) private var colorScheme
    let geometry: DropGeometry
    let pointer: CGPoint
    /// The area the drop moves over, in the same coordinates as `geometry`.
    let size: CGSize

    /// Room around the area for what reaches past it: the lifted drop, its shadow.
    private let margin: CGFloat = 16

    var body: some View {
        if geometry.isVisible {
            let drop = geometry.offsetBy(dx: margin, dy: margin)
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    context.translateBy(x: margin, y: margin)
                    paint(in: &context)
                }
                if let library = LensShaders.library {
                    Rectangle()
                        .fill(.white)
                        .colorEffect(Shader(function: ShaderFunction(library: library, name: "glassLight"),
                                            arguments: drop.shaderShape + [
                                                .float(min(drop.lift, 1)),
                                                .float(drop.motion),
                                                .float(colorScheme == .light ? 1 : 0),
                                            ]))
                }
            }
            .frame(width: size.width + margin * 2, height: size.height + margin * 2)
            .offset(x: -margin, y: -margin)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func paint(in context: inout GraphicsContext) {
        let outline = geometry.outline
        // Faster than the glass shrinks, so a landing drop never shows two edges.
        let edges = geometry.lift * geometry.lift
        paintShadow(in: &context, outline: outline, opacity: edges)
        context.drawLayer { layer in
            layer.opacity = edges
            layer.clip(to: outline)
            paintBloom(in: &layer)
        }
    }

    /// Cast on what is below, and kept off the inside of the drop: seen through clear
    /// glass, a shadow underneath reads as a smudge.
    private func paintShadow(in context: inout GraphicsContext, outline: Path, opacity: CGFloat) {
        context.drawLayer { layer in
            layer.opacity = opacity
            var outside = Path(CGRect(x: -margin, y: -margin,
                                      width: size.width + margin * 2, height: size.height + margin * 2))
            outside.addPath(outline)
            layer.clip(to: outside, style: FillStyle(eoFill: true))

            let box = geometry.bounds.insetBy(dx: -7, dy: -6).offsetBy(dx: 0, dy: 3)
            let radius = box.height / 2
            layer.translateBy(x: box.midX, y: box.midY)
            layer.scaleBy(x: box.width / box.height, y: 1)
            layer.fill(Path(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)),
                       with: .radialGradient(Gradient(stops: [.init(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.12),
                                                                    location: 0.6),
                                                              .init(color: .black.opacity(0), location: 1)]),
                                             center: .zero, startRadius: 0, endRadius: radius))
        }
    }

    /// A soft bloom under the pointer - the response system glass gives to a touch.
    /// The rest of the drop's light is the shader's, worked out from its shape.
    private func paintBloom(in context: inout GraphicsContext) {
        let dark = colorScheme == .dark
        context.blendMode = dark ? .plusLighter : .normal
        let bounds = geometry.bounds
        let short = min(bounds.width, bounds.height)
        let radius = short * 0.8
        let inner = bounds.insetBy(dx: min(short * 0.3, bounds.width / 2), dy: min(short * 0.3, bounds.height / 2))
        let at = CGPoint(x: min(max(pointer.x, inner.minX), inner.maxX),
                         y: min(max(pointer.y, inner.minY), inner.maxY))
        context.fill(Path(ellipseIn: CGRect(x: at.x - radius, y: at.y - radius, width: radius * 2, height: radius * 2)),
                     with: .radialGradient(Gradient(colors: [.white.opacity(dark ? 0.08 : 0.16), .white.opacity(0)]),
                                           center: at, startRadius: 0, endRadius: radius))
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
