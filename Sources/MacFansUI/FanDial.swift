import SwiftUI
import FanKit

/// The blades, as a ring of narrow petals around a hub.
///
/// `spread` fattens each petal without moving its tip or its root. At 1 it is the
/// blade as drawn; wound up, neighbouring petals swell until they meet. That is
/// how the moving air is drawn - see `FanDial.wash` for why it is done with one
/// widening shape rather than a stack of copies.
struct FanBlades: Shape {
    var count: Int = 5
    var spread: Double = 1

    /// So a change of speed widens the petals over time instead of snapping them.
    var animatableData: Double {
        get { spread }
        set { spread = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let blades = max(count, 2)
        let side = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: origin.x + x * side, y: origin.y + y * side)
        }

        let half = 0.076 * max(spread, 0.01)

        var blade = Path()
        blade.move(to: point(0.5, 0.5))
        blade.addCurve(to: point(0.5, 0.1515),
                       control1: point(0.5, 0.303),
                       control2: point(0.5 - half, 0.197))
        blade.addCurve(to: point(0.5, 0.5),
                       control1: point(0.5 + half, 0.197),
                       control2: point(0.5, 0.303))
        blade.closeSubpath()

        var combined = Path()
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        for index in 0..<blades {
            let rotation = CGAffineTransform(translationX: centre.x, y: centre.y)
                .rotated(by: Double(index) * 2 * .pi / Double(blades))
                .translatedBy(x: -centre.x, y: -centre.y)
            combined.addPath(blade, transform: rotation)
        }
        return combined
    }
}

/// Where the blades have turned to, integrated frame by frame.
///
/// The angle used to be `timeIntervalSinceReferenceDate * rate`, which is the bug
/// that made the dial stutter. That reference date is some 8.1e8 seconds ago, so
/// the rate is multiplied by an enormous number: changing it by one rpm rewrites
/// the whole product and moves the blades about 10 degrees at random, and by ten
/// rpm about 99 degrees. A reading arrives every second, so once a second the
/// blades teleported - forwards or backwards - by up to forty-five frames' worth
/// of rotation. Real motion at 2600 rpm is 2.17 degrees per frame.
///
/// Advancing by `rate * elapsed` instead means a change of rate changes only what
/// happens next, which is what the old comment claimed and did not do.
@MainActor
final class BladeSpin {
    private(set) var angle: Double = 0
    private var last: Date?

    func advance(to now: Date, rate: Double) -> Double {
        defer { last = now }
        guard let last else { return angle }
        // A hidden window, a sleeping machine or a paused preview can hand back a
        // gap of seconds. Spinning through all of it at once would look like the
        // very glitch this is here to remove, so a frame is a frame.
        let elapsed = min(max(now.timeIntervalSince(last), 0), 1.0 / 20)
        angle = (angle + rate * elapsed).truncatingRemainder(dividingBy: 360)
        return angle
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

    private static let bladeCount = 5
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

    @State private var spin = BladeSpin()

    /// Share of the fan's top speed, not of the span above its minimum: measured from
    /// the minimum, an idling fan fills under one percent of the arc and the dial reads
    /// as broken.
    private var fraction: Double {
        guard rpm > 0, limits.maxRPM > 0 else { return 0 }
        return min(max(rpm / limits.maxRPM, 0), 1)
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

    private var arcStyle: AnyShapeStyle {
        if alert { return AnyShapeStyle(Palette.critical) }
        return controlled
            ? AnyShapeStyle(AngularGradient(
                colors: [Palette.calm, Palette.series[2], Palette.calm],
                center: .center))
            : AnyShapeStyle(Palette.ink.opacity(0.42))
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

    private var arc: some View {
        Circle()
            .trim(from: 0, to: 0.75 * fraction)
            .stroke(arcStyle, style: StrokeStyle(lineWidth: size * 0.023, lineCap: .round))
            .rotationEffect(.degrees(135))
            // A spring, not a timing curve. Readings land about once a second and an
            // ease-out finished in 0.6s, so the arc moved, stopped dead, waited, then
            // moved again - the stepping this was reported for. A spring retargets
            // mid-flight from wherever it has got to, so consecutive readings join up
            // into one continuous travel.
            .animation(.smooth(duration: 0.9), value: fraction)
            .animation(.smooth(duration: 0.4), value: alert)
            .animation(.smooth(duration: 0.4), value: controlled)
    }

    /// The turning disc.
    ///
    /// Sixty frames a second, not the display's own rate: this is a decorative
    /// spinner and nobody can tell 120 from 60 on it. Paused outright when the fan
    /// has stopped, so a quiet machine wakes nothing at all.
    private var disc: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: spinRate == 0)) { context in
            let angle = spin.advance(to: context.date, rate: spinRate)
            TurningDisc(size: size, blades: Self.bladeCount, spread: blurred,
                        tint: bladeColor, ink: bladeOpacity)
                // The closure runs every frame, so without this the gradients and
                // their stops were rebuilt sixty times a second per dial. Nothing
                // in the disc depends on the clock except how far it has turned.
                .equatable()
                .rotationEffect(.degrees(angle))
                .animation(.smooth(duration: 0.9), value: blurred)
                .animation(.smooth(duration: 0.5), value: bladeOpacity)
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

/// The blades and the air they drag, drawn once and then simply turned.
///
/// Split out and made `Equatable` so the frame loop cannot force it to redraw.
/// It lives inside a `TimelineView`, whose closure runs on every frame, and
/// building the angular gradient, its stops and the radial mask sixty times a
/// second for each dial on screen was the single most expensive thing the app
/// did. None of it depends on the clock - only the rotation does, and that is
/// applied outside. Now it is rebuilt when the speed step changes, ten times
/// across the fan's whole range.
private struct TurningDisc: View, Equatable {
    let size: CGFloat
    let blades: Int
    /// How far from "separate petals" towards "a turning disc", 0 to 1.
    let spread: Double
    let tint: Color
    let ink: Double

    static func == (a: TurningDisc, b: TurningDisc) -> Bool {
        a.size == b.size && a.blades == b.blades && a.tint == b.tint
            && abs(a.spread - b.spread) < 0.0001 && abs(a.ink - b.ink) < 0.0001
    }

    var body: some View {
        ZStack {
            air.rotationEffect(.degrees(-lag))
            FanBlades(count: blades, spread: 1 + 0.9 * spread)
                .fill(tint)
                // A fan at full tilt shows no distinct blade, so the crisp set
                // recedes as the air takes over, leaving a hint of structure.
                .opacity(ink * (1 - 0.3 * spread))
        }
        .frame(width: size, height: size)
        // Flattened to one texture so the frame loop transforms a bitmap rather
        // than re-running a blur and two gradient fills through the compositor on
        // every frame of every dial on screen.
        .drawingGroup()
    }

    /// The air the blades drag with them: one soft lobe per blade, sweeping round
    /// a little behind them.
    ///
    /// An angular gradient, not copies of the blade. Copies were tried twice - at
    /// any useful spacing they read as a row of separate smudges, and closing that
    /// spacing takes enough of them that the hub collects a bright blot where they
    /// all converge. A gradient has nothing to band: it is smooth by construction,
    /// costs one fill, and spreads evenly into the gap between blades, which is
    /// the whole point of drawing it.
    private var air: some View {
        Circle()
            .fill(AngularGradient(stops: stops, center: .center))
            // The air lives where the blades sweep and nowhere else. The petals
            // reach 0.70 of the dial's radius, so past that the glow would be a
            // halo around the gauge rather than air inside it.
            .mask(
                RadialGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.18),
                        .init(color: .white, location: 0.40),
                        .init(color: .white, location: 0.62),
                        .init(color: .clear, location: 0.76),
                    ],
                    center: .center, startRadius: 0, endRadius: size / 2)
            )
            .opacity(ink * 1.15 * spread)
            .blur(radius: size * 0.018)
    }

    /// Clear at each blade line, solid halfway between: the lobes land in the
    /// gaps. Both ends of every ramp are explicit, so the sweep closes on itself
    /// without a seam.
    private var stops: [Gradient.Stop] {
        var stops: [Gradient.Stop] = []
        for lobe in 0...blades {
            let base = Double(lobe) / Double(blades)
            stops.append(.init(color: tint.opacity(0), location: base))
            if lobe < blades {
                stops.append(.init(color: tint, location: base + 0.5 / Double(blades)))
            }
        }
        return stops
    }

    /// The air lags a little behind the blade that threw it.
    private var lag: Double {
        spread * (360 / Double(blades)) * 0.22
    }
}
