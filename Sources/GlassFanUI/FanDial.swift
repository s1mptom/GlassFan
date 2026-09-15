import SwiftUI
import AppKit
import FanKit

/// The blades and hub, from `FanGeometry`: six swept crescents, tips at 0.35 of
/// the frame's side - where the dial's blades have always reached.
struct FanBlades: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        return Path(FanGeometry.path(centre: CGPoint(x: rect.midX, y: rect.midY),
                                     radius: side * 0.3485))
    }
}

/// The fan gauge: an arc for how fast it is turning, blades that turn at a speed
/// proportional to the rpm, and the number in the middle.
struct FanDial: View {
    let rpm: Double
    let limits: FanLimits
    let controlled: Bool
    /// The fan is in trouble - running away on the emergency rule, or refusing the
    /// writes sent to it. Either way the gauge should not look like business as usual.
    var alert = false
    var size: CGFloat = 132
    var showsCaption = true
    /// At sidebar size the reading is already spelled out next to the dial, and a
    /// second copy inside it just crowds the blades.
    var showsValue = true

    /// The disc runs at one of ten speeds rather than at a speed computed from the
    /// reading.
    ///
    /// Nothing here is a real rotation anyway - a fan at 2600 rpm turns 43 times a
    /// second and would strobe - so tracking the reading exactly buys no honesty,
    /// while a reading that wanders by twenty rpm would keep nudging the speed and
    /// the width of the air. Banding the range into steps means the disc holds one
    /// speed until the fan has actually moved up or down a notch.
    private static let speedSteps = 10
    private static let topSpinRate: Double = 300

    // A constant, not a var: a private var with a default value makes the
    // memberwise initializer private under Swift 6.2 (Xcode 26), which is what the
    // release builds use.
    private let visibility = WindowVisibility.shared
    @Environment(\.colorScheme) private var scheme
    @State private var discImage: CGImage?

    /// Share of the fan's top speed, not of the span above its minimum: measured from
    /// the minimum, an idling fan fills under one percent of the arc and the dial reads
    /// as broken.
    ///
    /// Computed from the rpm rounded to twenty. A real fan's reading wanders by a
    /// few rpm every second, and every wander re-launched the arc's spring; a
    /// spring most of a second long re-launched every second is an animation that
    /// never stops - and every frame of it is a display cycle for the window, in
    /// which AppKit lays out whatever is dirty. On the overview that is Swift
    /// Charts, which is not cheap to lay out, a hundred and twenty times a second,
    /// on account of a dial moving by one part in five thousand. With the window
    /// closed, too.
    private var fraction: Double {
        guard rpm > 0, limits.maxRPM > 0 else { return 0 }
        let settled = (rpm / 50).rounded() * 50
        return min(max(settled / limits.maxRPM, 0), 1)
    }

    /// Which of the ten speeds this reading falls in. Zero only when the fan has
    /// actually stopped, which on Apple silicon it does.
    private var speedLevel: Int {
        guard rpm > 0, limits.maxRPM > 0 else { return 0 }
        let share = min(max(rpm / limits.maxRPM, 0), 1)
        return max(Int((share * Double(Self.speedSteps)).rounded(.up)), 1)
    }

    /// Degrees per second: a legible stand-in that still reads faster when the fan
    /// is faster.
    private var spinRate: Double {
        Double(speedLevel) / Double(Self.speedSteps) * Self.topSpinRate
    }

    /// How far from "five petals" towards "a turning disc" this speed is.
    private var blurred: Double {
        Double(speedLevel) / Double(Self.speedSteps)
    }

    private var bladeColor: Color {
        alert ? Palette.critical : (controlled ? Palette.blade : Palette.ink)
    }

    /// Faint while stopped, so a still fan does not draw the eye; a turning one earns
    /// a little more presence.
    private var bladeOpacity: Double {
        rpm <= 0 ? 0.07 : 0.16
    }

    var body: some View {
        ZStack {
            track
            arc
            disc
            readout
        }
        .frame(width: size, height: size)
        // An arc, turning blades and a number say nothing to VoiceOver on their own,
        // so the dial speaks as one control instead of as its parts.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(alert
                            ? L10n.t("Вентилятор, нужно внимание", "Fan, needs attention")
                            : controlled
                              ? L10n.t("Вентилятор под управлением", "Fan under control")
                              : L10n.t("Вентилятор", "Fan"))
        .accessibilityValue(L10n.t("\(Format.rpm(rpm)) оборотов в минуту",
                                   "\(Format.rpm(rpm)) rpm"))
    }

    private var track: some View {
        Circle()
            .trim(from: 0, to: 0.75)
            .stroke(Palette.ink.opacity(0.09),
                    style: StrokeStyle(lineWidth: size * 0.023, lineCap: .round))
            .rotationEffect(.degrees(135))
    }

    /// The speed arc, drawn and animated by Core Animation.
    ///
    /// It was a SwiftUI shape with `.animation(.smooth)` on its trim. That kept
    /// the shape in an animation that never quite settled, and a shape in
    /// flight is re-rasterised by CoreGraphics on every frame - a gradient
    /// stroke, twice, at the display's refresh rate. Measured with the disc
    /// paused and the chart off: 15.9% of a core with those modifiers, 2.0%
    /// without. A `strokeEnd` on a shape layer animates on the render server
    /// and costs the process nothing after the write.
    private var arc: some View {
        ArcLayer(size: size, fraction: fraction,
                 colors: arcColors.map { $0.cgColor })
            .frame(width: size, height: size)
    }

    private var arcColors: [NSColor] {
        if alert { return [NSColor(Palette.critical), NSColor(Palette.critical)] }
        return controlled
            ? [NSColor(Palette.calm), NSColor(Palette.series[2])]
            : [NSColor(Palette.ink).withAlphaComponent(0.42),
               NSColor(Palette.ink).withAlphaComponent(0.42)]
    }

    /// What the disc looks like at this speed step, as a key for the render.
    private struct DiscKey: Equatable {
        let size: CGFloat; let spread: Double; let tint: Color; let ink: Double
        let scheme: ColorScheme
    }

    private var discKey: DiscKey {
        DiscKey(size: size, spread: blurred, tint: bladeColor, ink: bladeOpacity, scheme: scheme)
    }

    /// The turning disc: a picture, turned by the render server.
    ///
    /// The blades used to turn in SwiftUI, a `TimelineView` re-evaluating the
    /// dial sixty times a second. The dial itself was cheap; the problem was
    /// what every one of those frames did to the rest of the window. Any
    /// animation in a SwiftUI window makes `NSHostingView.layout()` walk the
    /// whole tree and recompute its preferences on each frame, and on the
    /// overview that tree contains a chart of seven hundred marks. Bisected
    /// with the window closed: two dials, 19% of a core; no dials, 5.6%.
    ///
    /// So the disc is rendered to a bitmap once per speed step - ten of them
    /// across the range - and a CABasicAnimation on the layer turns it. That
    /// runs on the render server, on the GPU, and the process does nothing per
    /// frame at all. A change of speed reads the angle back from the
    /// presentation layer and restarts from there, so nothing jumps.
    private var disc: some View {
        SpinningDisc(image: discImage, size: size, degreesPerSecond: spinRate,
                     paused: spinRate == 0 || !visibility.isVisible)
            .frame(width: size, height: size)
            .task(id: discKey) {
                let renderer = ImageRenderer(content:
                    TurningDisc(size: size, spread: blurred,
                                tint: bladeColor, ink: bladeOpacity)
                        .environment(\.colorScheme, scheme))
                renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
                discImage = renderer.cgImage
            }
    }

    private var readout: some View {
        Group {
            if showsValue {
                VStack(spacing: 0) {
                    Text(Format.rpm(rpm))
                        .font(.system(size: size * 0.30, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.ink)
                        // Digits roll to the new value rather than being swapped out
                        // from under the eye.
                        // Deliberately not `.contentTransition(.numericText)`.
                        // Rolling the digits looks lovely and, measured against
                        // the same build without it, cost about fifteen points of
                        // a core: it morphs glyphs at this size twice a second,
                        // once per dial. A fan utility that warms the machine to
                        // animate its own readout has argued itself out of a job.
                    if showsCaption {
                        Text(L10n.t("об/мин", "rpm"))
                            .font(.system(size: size * 0.08))
                            .foregroundStyle(Palette.ink.opacity(0.4))
                            .offset(y: -2)
                    }
                }
            }
        }
    }
}

/// The blades and the wake they drag. Never on screen as a view: `FanDial`
/// renders it to a bitmap and hands the bitmap to `SpinningDisc`.
private struct TurningDisc: View {
    let size: CGFloat
    /// How far towards full speed, 0 to 1.
    let spread: Double
    let tint: Color
    let ink: Double

    var body: some View {
        ZStack {
            // Behind each blade only - see `FanGeometry.wake`.
            ZStack {
                ForEach(Array(FanGeometry.wake(spread: spread).enumerated()), id: \.offset) { _, ghost in
                    FanBlades()
                        .fill(tint)
                        .opacity(ghost.opacity)
                        .rotationEffect(.radians(ghost.angle))
                }
            }
            .blur(radius: size * 0.005)
            // Every copy converges on the hub; faded there, or they collect into a
            // bright ring just outside it.
            .mask(
                RadialGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.17),
                        .init(color: .white, location: 0.24),
                        .init(color: .white, location: 1),
                    ],
                    center: .center, startRadius: 0, endRadius: size / 2)
            )
            FanBlades().fill(tint)
        }
        // One layer, faded as a whole: the crisp blades cover their own wake
        // where they overlap it, as solid blades would.
        .compositingGroup()
        .opacity(ink)
        .frame(width: size, height: size)
    }
}

/// A bitmap on a layer, turned by Core Animation at a rate in degrees per
/// second. Speed changes are continuous: the current angle is read from the
/// presentation layer and the new animation starts there.
///
/// Layer-hosting, not layer-backed: the view supplies its own `CALayer` before
/// `wantsLayer` is set, so AppKit neither manages the layer's display nor
/// wraps writes to it in implicit animations. The first version was
/// layer-backed and rewrote `frame`, `position` and `contents` on every
/// SwiftUI update; AppKit answered each write with an `NSAnimationContext`
/// group and a redisplay, and with the window shown the two dials alone cost
/// 26% of a core. Now nothing here is written unless it changed, and every
/// write happens with implicit actions off.
private struct SpinningDisc: NSViewRepresentable {
    let image: CGImage?
    let size: CGFloat
    let degreesPerSecond: Double
    let paused: Bool

    final class Coordinator {
        /// The layer that turns. A sublayer, not the view's own: AppKit re-sets
        /// the geometry of a view's root layer on every layout pass and assumes
        /// its anchor point is the corner, so an anchor moved to the centre for
        /// the rotation put the centre of the disc at the corner of the view -
        /// the disc sat half a dial down and to the left of its gauge. A sublayer
        /// is ours alone.
        let disc = CALayer()
        var image: CGImage?
        var rate: Double = 0
        var size: CGFloat = 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        let root = CALayer()
        view.layer = root
        view.wantsLayer = true
        let disc = context.coordinator.disc
        disc.contentsGravity = .resizeAspect
        disc.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        disc.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        root.addSublayer(disc)
        apply(to: disc, context.coordinator)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        apply(to: context.coordinator.disc, context.coordinator)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        CGSize(width: size, height: size)
    }

    private func apply(to layer: CALayer, _ state: Coordinator) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        if state.size != size {
            state.size = size
            layer.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            layer.position = CGPoint(x: size / 2, y: size / 2)
        }
        if state.image !== image {
            state.image = image
            layer.contents = image
        }

        let wanted = paused ? 0 : max(degreesPerSecond, 0)
        guard wanted != state.rate else { return }
        state.rate = wanted

        let current = (layer.presentation() ?? layer)
            .value(forKeyPath: "transform.rotation.z") as? Double ?? 0
        layer.removeAnimation(forKey: "spin")
        layer.setValue(current, forKeyPath: "transform.rotation.z")
        guard wanted > 0 else { return }

        // Clockwise on screen: the layer's z axis points out of it, and AppKit's
        // coordinate space is not flipped, so a positive rotation is
        // counter-clockwise - hence the sign.
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = current
        turn.toValue = current - 2 * Double.pi
        turn.duration = 360 / wanted
        turn.repeatCount = .infinity
        turn.timingFunction = CAMediaTimingFunction(name: .linear)
        layer.add(turn, forKey: "spin")
    }
}

/// Three quarters of a circle, from bottom-left round to bottom-right, filled
/// to `fraction` of its length. A gradient layer masked by a shape layer, so the
/// stroke can carry two colours; the mask's `strokeEnd` is what moves, with
/// Core Animation's implicit animation doing the easing off-process.
private struct ArcLayer: NSViewRepresentable {
    let size: CGFloat
    let fraction: Double
    let colors: [CGColor]

    final class Coordinator {
        let gradient = CAGradientLayer()
        let mask = CAShapeLayer()
        var fraction: Double = -1
        var colors: [CGColor] = []
        var size: CGFloat = 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        let state = context.coordinator
        state.gradient.startPoint = CGPoint(x: 0, y: 0)
        state.gradient.endPoint = CGPoint(x: 1, y: 1)
        state.gradient.mask = state.mask
        state.mask.fillColor = nil
        state.mask.strokeColor = NSColor.black.cgColor
        state.mask.lineCap = .round
        state.mask.strokeStart = 0
        view.layer = state.gradient
        view.wantsLayer = true
        apply(state)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { apply(context.coordinator) }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        CGSize(width: size, height: size)
    }

    private func apply(_ state: Coordinator) {
        if state.size != size {
            state.size = size
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let bounds = CGRect(x: 0, y: 0, width: size, height: size)
            state.gradient.frame = bounds
            state.mask.frame = bounds
            state.mask.lineWidth = size * 0.023
            // The layer is not flipped: y is up and angles run counter-clockwise
            // from the x axis. The gauge sweeps from bottom-left (225 degrees)
            // over the top to bottom-right (-45 degrees), which on screen is
            // clockwise - decreasing angle, hence `clockwise: true`.
            let inset = size * 0.023 / 2
            let path = CGMutablePath()
            path.addArc(center: CGPoint(x: size / 2, y: size / 2), radius: size / 2 - inset,
                        startAngle: .pi * 1.25, endAngle: -.pi * 0.25, clockwise: true)
            state.mask.path = path
            CATransaction.commit()
        }
        if state.colors != colors {
            state.colors = colors
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.4)
            state.gradient.colors = colors
            CATransaction.commit()
        }
        if state.fraction != fraction {
            state.fraction = fraction
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.5)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
            state.mask.strokeEnd = fraction
            CATransaction.commit()
        }
    }
}
