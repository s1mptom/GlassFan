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
                              height: max(geometry.size.height - 34, 10))

            ZStack(alignment: .topLeading) {
                grid(in: plot)
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
        let y = plot.maxY - plot.height *
            (point.rpm - limits.minRPM) / max(limits.maxRPM - limits.minRPM, 1)
        return CGPoint(x: x, y: y)
    }

    private func point(from location: CGPoint, in plot: CGRect) -> CurvePoint {
        let ratioX = min(max((location.x - plot.minX) / plot.width, 0), 1)
        let ratioY = min(max((plot.maxY - location.y) / plot.height, 0), 1)
        return CurvePoint(
            temperature: (tempRange.lowerBound + ratioX * (tempRange.upperBound - tempRange.lowerBound)).rounded(),
            rpm: (limits.minRPM + ratioY * (limits.maxRPM - limits.minRPM)).rounded()
        )
    }

    // MARK: Layers

    private func grid(in plot: CGRect) -> some View {
        Canvas { context, _ in
            let line = Color.white.opacity(0.05)
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
                .fill(Color(red: 0.04, green: 0.06, blue: 0.10))
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
                let marker = position(CurvePoint(temperature: currentTemp, rpm: currentRPM), in: plot)
                Circle()
                    .fill(Palette.heat)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().strokeBorder(Palette.heat.opacity(0.25), lineWidth: 4))
                    .shadow(color: Palette.heat.opacity(0.7), radius: 7)
                    .position(marker)
                    .animation(.easeInOut(duration: 0.8), value: currentTemp)

                Text(String(format: "%.0f° · %.0f", currentTemp, currentRPM))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .glassSurface(cornerRadius: 999)
                    .position(x: min(marker.x + 64, plot.maxX - 24), y: max(marker.y - 18, plot.minY + 12))
                    .animation(.easeInOut(duration: 0.8), value: currentTemp)
            }
        }
    }

    private func axisLabels(in plot: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach([40.0, 60.0, 80.0, 100.0], id: \.self) { temperature in
                Text("\(Int(temperature))°")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
                    .position(x: position(CurvePoint(temperature: temperature, rpm: limits.minRPM), in: plot).x,
                              y: plot.maxY + 13)
            }
            ForEach([0.0, 0.5, 1.0], id: \.self) { fraction in
                Text("\(Int(limits.minRPM + fraction * (limits.maxRPM - limits.minRPM)))")
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.3))
                    .position(x: plot.minX - 20, y: plot.maxY - plot.height * fraction)
            }
        }
    }
}
