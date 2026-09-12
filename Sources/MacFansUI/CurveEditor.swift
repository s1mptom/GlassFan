import SwiftUI
import FanKit

/// Drag-to-edit fan curve. Swift Charts cannot do this, so the plot is drawn by hand.
///
/// X is temperature, Y is rpm. A live marker shows where the fan is sitting right now.
struct CurveEditor: View {
    @Binding var curve: FanCurve
    let limits: FanLimits
    let currentTemp: Double?
    let currentRPM: Double?
    var onCommit: () -> Void

    private let tempRange: ClosedRange<Double> = 30...100
    @State private var dragging: Int?

    var body: some View {
        GeometryReader { geometry in
            let plot = CGRect(x: 34, y: 8,
                              width: max(geometry.size.width - 44, 10),
                              height: max(geometry.size.height - 52, 10))

            ZStack(alignment: .topLeading) {
                grid(in: plot)
                minimumGuide(in: plot)
                curveShape(in: plot)
                liveMarker(in: plot)
                handles(in: plot)
                axisLabels(in: plot)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { location in
                guard plot.contains(location) else { return }
                curve.addPoint(point(from: location, in: plot))
                onCommit()
            }
        }
    }

    // MARK: Geometry

    private func position(_ point: CurvePoint, in plot: CGRect) -> CGPoint {
        let x = plot.minX + plot.width *
            (point.temperature - tempRange.lowerBound) / (tempRange.upperBound - tempRange.lowerBound)
        let y = plot.maxY - plot.height * point.rpm / max(limits.maxRPM, 1)
        return CGPoint(x: x, y: y)
    }

    private func point(from location: CGPoint, in plot: CGRect) -> CurvePoint {
        let ratioX = min(max((location.x - plot.minX) / plot.width, 0), 1)
        let ratioY = min(max((plot.maxY - location.y) / plot.height, 0), 1)
        return CurvePoint(
            temperature: (tempRange.lowerBound + ratioX * (tempRange.upperBound - tempRange.lowerBound)).rounded(),
            rpm: (ratioY * limits.maxRPM).rounded()
        )
    }

    // MARK: Layers

    private func grid(in plot: CGRect) -> some View {
        Canvas { context, _ in
            let line = Palette.ink.opacity(0.05)
            for temperature in stride(from: 40.0, through: 100.0, by: 20.0) {
                let x = position(CurvePoint(temperature: temperature, rpm: limits.minRPM), in: plot).x
                context.stroke(Path { $0.move(to: CGPoint(x: x, y: plot.minY))
                                      $0.addLine(to: CGPoint(x: x, y: plot.maxY)) },
                               with: .color(line), lineWidth: 1)
            }
            for fraction in stride(from: 0.0, through: 1.0, by: 0.25) {
                let y = plot.maxY - plot.height * fraction
                context.stroke(Path { $0.move(to: CGPoint(x: plot.minX, y: y))
                                      $0.addLine(to: CGPoint(x: plot.maxX, y: y)) },
                               with: .color(line), lineWidth: 1)
            }
        }
    }

    /// Where the SMC says the fan's minimum is. It is advice, not a floor - the
    /// hardware was asked for 1000, 500 and 0 and did as it was told - so the
    /// scale runs to zero and this line just says where "minimum" would have
    /// been. Below it the fan runs slow and, at zero, stops.
    private func minimumGuide(in plot: CGRect) -> some View {
        let y = position(CurvePoint(temperature: tempRange.lowerBound, rpm: limits.minRPM), in: plot).y
        return ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: CGPoint(x: plot.minX, y: y))
                path.addLine(to: CGPoint(x: plot.maxX, y: y))
            }
            .stroke(Palette.ink.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            Text(L10n.t("\(Format.rpm(limits.minRPM)) · минимум SMC",
                        "\(Format.rpm(limits.minRPM)) · SMC minimum"))
                .font(.system(size: 9.5))
                .monospacedDigit()
                .foregroundStyle(Palette.ink.opacity(0.32))
                .position(x: plot.maxX - 58, y: y - 9)
        }
        .allowsHitTesting(false)
    }

    private func curveShape(in plot: CGRect) -> some View {
        Canvas { context, _ in
            guard !curve.points.isEmpty else { return }
            var path = Path()
            let first = curve.points[0]
            path.move(to: CGPoint(x: plot.minX, y: position(first, in: plot).y))
            for point in curve.points {
                path.addLine(to: position(point, in: plot))
            }
            if let last = curve.points.last {
                path.addLine(to: CGPoint(x: plot.maxX, y: position(last, in: plot).y))
            }

            var fill = path
            fill.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
            fill.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
            fill.closeSubpath()
            context.fill(fill, with: .linearGradient(
                Gradient(colors: [Palette.calm.opacity(0.32), Palette.calm.opacity(0.02)]),
                startPoint: CGPoint(x: plot.midX, y: plot.minY),
                endPoint: CGPoint(x: plot.midX, y: plot.maxY)))
            context.stroke(path, with: .color(Palette.calm), lineWidth: 2.5)
        }
    }

    private func handles(in plot: CGRect) -> some View {
        ForEach(Array(curve.points.enumerated()), id: \.offset) { index, point in
            Circle()
                .fill(Palette.surface)
                .overlay(Circle().strokeBorder(Palette.calm, lineWidth: 2.5))
                .frame(width: 13, height: 13)
                .scaleEffect(dragging == index ? 1.25 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: dragging)
                .position(position(point, in: plot))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            dragging = index
                            curve.movePoint(at: index, to: self.point(from: value.location, in: plot))
                        }
                        .onEnded { _ in
                            dragging = nil
                            onCommit()
                        }
                )
                .onTapGesture(count: 2) {
                    curve.removePoint(at: index)
                    onCommit()
                }
        }
    }

    private func liveMarker(in plot: CGRect) -> some View {
        Group {
            if let currentTemp, let currentRPM {
                // Kept inside the plot. The plot's floor is the fan's SMC minimum,
                // but on Apple silicon a fan at rest reads 0 rpm - below that
                // floor - and the marker flew off the bottom of the editor. It
                // sits on the floor line instead, and the label says what the
                // fan is really doing.
                let raw = position(CurvePoint(temperature: currentTemp, rpm: currentRPM), in: plot)
                let marker = CGPoint(x: min(max(raw.x, plot.minX), plot.maxX),
                                     y: min(max(raw.y, plot.minY), plot.maxY))
                let nearFloor = marker.y > plot.maxY - 22
                Circle()
                    .fill(Palette.heat)
                    .frame(width: 11, height: 11)
                    // The halo was a live shadow on a dot that moves every second,
                    // which is an offscreen blur pass for something a ring draws
                    // just as well.
                    .overlay(Circle().strokeBorder(Palette.heat.opacity(0.25), lineWidth: 4))
                    .overlay(Circle().strokeBorder(Palette.heat.opacity(0.12), lineWidth: 9))
                    .position(marker)
                    .animation(.easeInOut(duration: 0.8), value: currentTemp)

                Text(String(format: "%.0f° · %.0f", currentTemp, currentRPM))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    // A plain capsule, not a glass surface. This label moves with
                    // every reading, and re-rendering a Liquid Glass material on
                    // something that is in motion a second out of every second is
                    // the most expensive thing on the screen for the least gain -
                    // it is a tooltip the size of a postage stamp.
                    .background(
                        Capsule()
                            .fill(Palette.surface.opacity(0.82))
                            .overlay(Capsule().strokeBorder(Palette.ink.opacity(0.12),
                                                            lineWidth: 0.5))
                    )
                    .position(x: min(marker.x + 52, plot.maxX - 46),
                              y: nearFloor ? marker.y - 20
                                           : min(max(marker.y, plot.minY + 12), plot.maxY - 12))
                    .animation(.easeInOut(duration: 0.8), value: currentTemp)
            }
        }
    }

    private func axisLabels(in plot: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            // Adding and removing points is a double click on nothing in
            // particular - undiscoverable unless it is said. It was a hover
            // tooltip, which was small, floated over the axis labels and looked
            // like it was trying to squeeze into the interface. A caption under
            // the plot is always there and in nobody's way.
            Text(L10n.t("Двойной клик — добавить точку, по точке — убрать",
                        "Double-click to add a point, or on one to remove it"))
                .font(.system(size: 11))
                .foregroundStyle(Palette.ink.opacity(0.35))
                .fixedSize()
                .offset(x: plot.minX, y: plot.maxY + 28)
            ForEach([40.0, 60.0, 80.0, 100.0], id: \.self) { temperature in
                Text("\(Int(temperature))°")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.ink.opacity(0.3))
                    .position(x: position(CurvePoint(temperature: temperature, rpm: limits.minRPM), in: plot).x,
                              y: plot.maxY + 13)
            }
            ForEach([0.0, 0.5, 1.0], id: \.self) { fraction in
                Text(Format.rpm(fraction * limits.maxRPM))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink.opacity(0.3))
                    .position(x: plot.minX - 20, y: plot.maxY - plot.height * fraction)
            }
        }
    }
}
