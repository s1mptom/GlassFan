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
/// One measure per chart on purpose: temperatures and rpm never share a y-axis, they
/// get their own chart stacked below.
struct TimeChart: View {
    let points: [SeriesPoint]
    let order: [String]
    let unit: String
    var includesZero: Bool = false
    var valueFormat: (Double) -> String

    @State private var hoverDate: Date?

    var body: some View {
        Chart {
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
                    .foregroundStyle(.secondary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartForegroundStyleScale(range: order.indices.map { Palette.color($0) })
        .chartYScale(domain: .automatic(includesZero: includesZero))
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(valueFormat(number)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.10))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.hour().minute())
                            .foregroundStyle(.secondary)
                    }
                }
            }
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
        VStack(alignment: .leading, spacing: 4) {
            Text(date, format: .dateTime.hour().minute().second())
                .font(.caption2)
                .foregroundStyle(.secondary)
            ForEach(entries.indices, id: \.self) { index in
                let entry = entries[index]
                HStack(spacing: 6) {
                    Circle().fill(entry.1).frame(width: 8, height: 8)
                    Text(entry.0).font(.caption)
                    Spacer(minLength: 8)
                    Text(format(entry.2)).font(.caption).monospacedDigit()
                }
            }
        }
        .padding(10)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .frame(maxWidth: 240)
    }
}

/// Identity is never colour alone: every series also gets a name and its current value.
struct ChartLegend: View {
    let names: [String]
    let values: [Double?]
    let format: (Double?) -> String

    var body: some View {
        FlowLayout(spacing: 12) {
            ForEach(names.indices, id: \.self) { index in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Palette.color(index))
                        .frame(width: 14, height: 3)
                    Text(names[index]).font(.caption)
                    Text(format(values.indices.contains(index) ? values[index] : nil))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Wraps legend chips onto as many rows as they need.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
