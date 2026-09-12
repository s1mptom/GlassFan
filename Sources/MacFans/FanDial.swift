import SwiftUI
import FanKit

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
            : AnyShapeStyle(Color.white.opacity(0.42))
    }

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(.white.opacity(0.09), style: StrokeStyle(lineWidth: size * 0.023, lineCap: .round))
                .rotationEffect(.degrees(135))

            Circle()
                .trim(from: 0, to: 0.75 * fraction)
                .stroke(arcStyle, style: StrokeStyle(lineWidth: size * 0.023, lineCap: .round))
                .rotationEffect(.degrees(135))
                .animation(.easeOut(duration: 0.6), value: fraction)

            TimelineView(.animation) { context in
                let seconds = context.date.timeIntervalSinceReferenceDate
                Image(systemName: "fan.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(controlled ? Color(red: 0.81, green: 0.90, blue: 1.0) : .white)
                    .opacity(rpm < 60 ? 0.07 : 0.15)
                    .frame(width: size * 0.62, height: size * 0.62)
                    .rotationEffect(.degrees(seconds * spinRate))
            }

            VStack(spacing: 0) {
                Text(Format.rpm(rpm))
                    .font(.system(size: size * 0.30, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                if showsCaption {
                    Text(L10n.t("об/мин", "rpm"))
                        .font(.system(size: size * 0.08))
                        .foregroundStyle(.white.opacity(0.4))
                        .offset(y: -2)
                }
            }
        }
        .frame(width: size, height: size)
    }
}
