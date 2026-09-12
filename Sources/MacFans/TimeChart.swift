import SwiftUI
import Charts
import FanKit

struct SeriesPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let series: String
}

/// A line chart over time with a crosshair readout.
///
/// One measure per chart on purpose: temperatures and rpm never share a y-axis - they
/// get their own chart. The line traces itself in on appear, which is the only motion
/// here; live updates just move the data.
struct TimeChart: View {
    let points: [SeriesPoint]
    let order: [String]
    let unit: String
    var includesZero: Bool = false
    /// Explicit y range. Needed whenever an area is drawn: an AreaMark anchors to zero
    /// and drags the scale down with it, which flattens a band of temperatures into the
    /// top quarter of the plot.
    var yDomain: ClosedRange<Double>?
    /// Fills under the first series, to give the chart some weight without adding ink
    /// to every line.
    var areaUnderFirst: Bool = false
    var valueFormat: (Double) -> String

    @State private var hoverDate: Date?
    @State private var traced: CGFloat = 0

    private var firstSeries: String? { order.first }

    /// Always an explicit range: `.automatic` would let an AreaMark anchor the scale to
    /// zero and squash the lines into the top of the plot.
    private var effectiveDomain: ClosedRange<Double> {
        if let yDomain { return yDomain }
        let values = points.map(\.value)
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        if includesZero { return 0...(high * 1.08 + 1) }
        let padding = max((high - low) * 0.12, 1)
        return (low - padding)...(high + padding)
    }

    var body: some View {
        Chart {
            if areaUnderFirst, let firstSeries {
                ForEach(points.filter { $0.series == firstSeries }) { point in
                    AreaMark(
                        x: .value(L10n.t("Время", "Time"), point.date),
                        y: .value(unit, point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(colors: [Palette.color(0).opacity(0.26), .clear],
                                       startPoint: .top, endPoint: .bottom)
                    )
                }
            }

            ForEach(points) { point in
                LineMark(
                    x: .value(L10n.t("Время", "Time"), point.date),
                    y: .value(unit, point.value)
                )
                .foregroundStyle(by: .value(L10n.t("Датчик", "Sensor"), point.series))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
            }

            if let hoverDate {
                RuleMark(x: .value(L10n.t("Время", "Time"), hoverDate))
                    .foregroundStyle(.white.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartForegroundStyleScale(range: order.indices.map { Palette.color($0) })
        .chartYScale(domain: effectiveDomain)
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.06))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(valueFormat(number))
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.32))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.05))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.hour().minute())
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.32))
                    }
                }
            }
        }
        .mask(alignment: .leading) {
            GeometryReader { geometry in
                Rectangle().frame(width: geometry.size.width * traced)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).delay(0.15)) { traced = 1 }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let plotFrame = proxy.plotFrame else { return }
                            let x = location.x - geometry[plotFrame].origin.x
                            hoverDate = proxy.value(atX: x, as: Date.self)
                        case .ended:
                            hoverDate = nil
                        }
                    }
            }
        }
        .overlay(alignment: .topTrailing) {
            if let hoverDate, let readout = readout(at: hoverDate) {
                ChartTooltip(date: hoverDate, entries: readout, format: valueFormat)
                    .padding(6)
            }
        }
    }

    private func readout(at date: Date) -> [(String, Color, Double)]? {
        guard !points.isEmpty else { return nil }
        var result: [(String, Color, Double)] = []
        for (index, series) in order.enumerated() {
            let candidates = points.filter { $0.series == series }
            guard let nearest = candidates.min(by: {
                abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
            }) else { continue }
            result.append((series, Palette.color(index), nearest.value))
        }
        return result.isEmpty ? nil : result
    }
}

struct ChartTooltip: View {
    let date: Date
    let entries: [(String, Color, Double)]
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(date, format: .dateTime.hour().minute().second())
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
            ForEach(entries.indices, id: \.self) { index in
                let entry = entries[index]
                HStack(spacing: 7) {
                    Capsule().fill(entry.1).frame(width: 12, height: 2.5)
                    Text(entry.0).font(.system(size: 11)).foregroundStyle(.white.opacity(0.85))
                    Spacer(minLength: 10)
                    Text(format(entry.2))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(11)
        .glassSurface(cornerRadius: 12)
        .frame(maxWidth: 250)
    }
}

/// Identity is never colour alone: every series also gets a name and its current value.
struct ChartLegend: View {
    let names: [String]
    let values: [Double?]
    var trailing: String?
    let format: (Double?) -> String

    var body: some View {
        HStack(spacing: 20) {
            ForEach(names.indices, id: \.self) { index in
                HStack(spacing: 7) {
                    Capsule()
                        .fill(Palette.color(index))
                        .frame(width: 13, height: 2.5)
                    Text(names[index])
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.72))
                    Text(format(values.indices.contains(index) ? values[index] : nil))
                        .font(.system(size: 11.5))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.42))
                }
            }
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.28))
            }
        }
    }
}
