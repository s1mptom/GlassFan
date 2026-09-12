import SwiftUI
import FanKit

/// The four blades from the design, ported curve for curve rather than approximated.
///
/// Each blade is a narrow petal from the hub to the rim: move to the centre, out to the
/// tip, back to the centre. The earlier version used control points twice this wide and
/// read as a blob, which is why it got replaced by a system glyph - this is the fix.
struct FanBlades: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: origin.x + x * side, y: origin.y + y * side)
        }

        var blade = Path()
        blade.move(to: point(0.5, 0.5))
        blade.addCurve(to: point(0.5, 0.1515),
                       control1: point(0.5, 0.303),
                       control2: point(0.424, 0.197))
        blade.addCurve(to: point(0.5, 0.5),
                       control1: point(0.576, 0.197),
                       control2: point(0.5, 0.303))
        blade.closeSubpath()

        var combined = Path()
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        for index in 0..<4 {
            let rotation = CGAffineTransform(translationX: centre.x, y: centre.y)
                .rotated(by: Double(index) * .pi / 2)
                .translatedBy(x: -centre.x, y: -centre.y)
            combined.addPath(blade, transform: rotation)
        }
        return combined
    }
}

/// The fan gauge: an arc for how fast it is turning, blades that actually turn at a
/// speed proportional to the rpm, and the number in the middle.
///
/// The angle is computed from the clock rather than driven by a repeating animation,
/// so a change in rpm changes the speed smoothly instead of restarting the spin.
struct FanDial: View {
    let rpm: Double
    let limits: FanLimits
    let controlled: Bool
    var size: CGFloat = 132
    var showsCaption = true
    /// At sidebar size the reading is already spelled out next to the dial, and a
    /// second copy inside it just crowds the blades.
    var showsValue = true

    /// Share of the fan's top speed, not of the span above its minimum: measured from
    /// the minimum, an idling fan fills under one percent of the arc and the dial reads
    /// as broken.
    private var fraction: Double {
        guard rpm > 0, limits.maxRPM > 0 else { return 0 }
        return min(max(rpm / limits.maxRPM, 0), 1)
    }

    /// Degrees per second. Real fan speed would be a blur, so this is a legible stand-in
    /// that still reads faster when the fan is faster.
    private var spinRate: Double {
        rpm < 60 ? 0 : min(rpm / 20, 320)
    }

    private var arcStyle: AnyShapeStyle {
        controlled
            ? AnyShapeStyle(AngularGradient(
                colors: [Palette.calm, Palette.series[2], Palette.calm],
                center: .center))
            : AnyShapeStyle(Palette.ink.opacity(0.42))
    }

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Palette.ink.opacity(0.09), style: StrokeStyle(lineWidth: size * 0.023, lineCap: .round))
                .rotationEffect(.degrees(135))

            Circle()
                .trim(from: 0, to: 0.75 * fraction)
                .stroke(arcStyle, style: StrokeStyle(lineWidth: size * 0.023, lineCap: .round))
                .rotationEffect(.degrees(135))
                .animation(.easeOut(duration: 0.6), value: fraction)

            TimelineView(.animation) { context in
                let seconds = context.date.timeIntervalSinceReferenceDate
                FanBlades()
                    .fill(controlled ? Palette.blade : Palette.ink)
                    .opacity(rpm < 60 ? 0.07 : 0.16)
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(seconds * spinRate))
            }

            if showsValue {
                VStack(spacing: 0) {
                    Text(Format.rpm(rpm))
                        .font(.system(size: size * 0.30, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.ink)
                    if showsCaption {
                        Text(L10n.t("об/мин", "rpm"))
                            .font(.system(size: size * 0.08))
                            .foregroundStyle(Palette.ink.opacity(0.4))
                            .offset(y: -2)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        // An arc, four turning blades and a number say nothing to VoiceOver on their
        // own, so the dial speaks as one control instead of as its parts.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(controlled
                            ? L10n.t("Вентилятор под управлением", "Fan under control")
                            : L10n.t("Вентилятор", "Fan"))
        .accessibilityValue(L10n.t("\(Format.rpm(rpm)) оборотов в минуту",
                                   "\(Format.rpm(rpm)) rpm"))
    }
}
