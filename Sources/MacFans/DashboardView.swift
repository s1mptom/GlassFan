import SwiftUI
import Charts
import FanKit

struct DashboardView: View {
    @Environment(DaemonClient.self) private var client
    @State private var window: TimeWindow = .fifteen

    enum TimeWindow: Int, CaseIterable, Identifiable {
        case five = 300, fifteen = 900, thirty = 1800
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .five: return L10n.t("5 мин", "5 min")
            case .fifteen: return L10n.t("15 мин", "15 min")
            case .thirty: return L10n.t("30 мин", "30 min")
            }
        }
    }

    private var trackedKeys: [String] {
        let keys = client.config?.trackedSensors ?? SensorCatalog.defaultTracked
        let available = Set((client.snapshot?.sensors ?? []).map(\.key))
        return Array(keys.filter(available.contains).prefix(6))
    }

    private var samples: [HistorySample] {
        let cutoff = Date().timeIntervalSince1970 - Double(window.rawValue)
        let recent = client.history.filter { $0.t >= cutoff }
        return Self.downsample(recent, to: 300)
    }

    /// Swift Charts slows to a crawl on thousands of marks; the eye cannot use them either.
    static func downsample(_ samples: [HistorySample], to limit: Int) -> [HistorySample] {
        guard samples.count > limit, limit > 0 else { return samples }
        let stride = Int((Double(samples.count) / Double(limit)).rounded(.up))
        return samples.enumerated().compactMap { $0.offset % stride == 0 ? $0.element : nil }
    }

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    filters
                    tiles
                    temperatureCard
                    fanCard
                }
            }
            .padding(22)
        }
        .scrollContentBackground(.hidden)
    }

    private var filters: some View {
        HStack {
            Picker("", selection: $window) {
                ForEach(TimeWindow.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
            Spacer()
        }
    }

    // MARK: Headline numbers

    private var tiles: some View {
        FlowLayout(spacing: 12) {
            ForEach(tileData, id: \.0) { tile in
                StatTile(title: tile.0, value: tile.1, caption: tile.2, tint: tile.3)
            }
        }
    }

    private var tileData: [(String, String, String, Color)] {
        var result: [(String, String, String, Color)] = []
        for group in [SensorGroup.cpu, .gpu, .comfort, .storage] {
            let sensors = client.sensors(in: group)
            guard let hottest = sensors.max(by: { $0.value < $1.value }) else { continue }
            result.append((group.title,
                           Format.temperature(hottest.value),
                           hottest.key,
                           heatColor(hottest.value)))
        }
        for fan in client.snapshot?.fans ?? [] {
            let caption: String
            if fan.writeError != nil {
                caption = L10n.t("запись отклонена", "write refused")
            } else if fan.forced {
                caption = L10n.t("под управлением", "controlled") + " · " + fan.mode.rawValue
            } else {
                caption = L10n.t("система", "system")
            }
            result.append((L10n.t("Вентилятор \(fan.index + 1)", "Fan \(fan.index + 1)"),
                           Format.rpm(fan.actualRPM),
                           caption,
                           fan.writeError != nil ? Palette.warning
                               : (fan.emergency ? Palette.critical : Palette.calm)))
        }
        return result
    }

    private func heatColor(_ temperature: Double) -> Color {
        switch temperature {
        case ..<65: return Palette.calm
        case ..<85: return Palette.warning
        default: return Palette.critical
        }
    }

    // MARK: Charts

    private var temperatureCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("Температуры", "Temperatures"))
                .font(.headline)

            let names = trackedKeys.map { SensorCatalog.info(for: $0).name }
            let points = samples.flatMap { sample in
                trackedKeys.compactMap { key -> SeriesPoint? in
                    guard let value = sample.temps[key] else { return nil }
                    return SeriesPoint(date: Date(timeIntervalSince1970: sample.t),
                                       value: value,
                                       series: SensorCatalog.info(for: key).name)
                }
            }

            if points.isEmpty {
                DataHint()
            } else {
                TimeChart(points: points, order: names, unit: "°C") {
                    String(format: "%.0f°", $0)
                }
                .frame(height: 148)

                ChartLegend(names: names,
                            values: trackedKeys.map { client.reading(for: $0) }) {
                    Format.temperatureFine($0)
                }
            }
        }
        .glassCard()
    }

    private var fanCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("Обороты вентиляторов", "Fan speed"))
                .font(.headline)

            let fans = client.snapshot?.fans ?? []
            let names = fans.map { L10n.t("Вентилятор \($0.index + 1)", "Fan \($0.index + 1)") }
            let points = samples.flatMap { sample in
                sample.fanRPM.enumerated().compactMap { index, rpm -> SeriesPoint? in
                    guard index < names.count else { return nil }
                    return SeriesPoint(date: Date(timeIntervalSince1970: sample.t),
                                       value: rpm,
                                       series: names[index])
                }
            }

            if points.isEmpty {
                DataHint()
            } else {
                TimeChart(points: points, order: names, unit: "rpm", includesZero: true) {
                    String(format: "%.0f", $0)
                }
                .frame(height: 104)

                ChartLegend(names: names, values: fans.map { $0.actualRPM }) {
                    Format.rpm($0) + " rpm"
                }
            }
        }
        .glassCard()
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let caption: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 27, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 128, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .glassSurface(cornerRadius: 16)
    }
}

/// Says which of the two silences this is: no daemon at all, or a daemon that has
/// simply not produced a second sample yet.
struct DataHint: View {
    @Environment(DaemonClient.self) private var client

    var body: some View {
        HStack {
            Spacer()
            if client.isConnected {
                VStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(L10n.t("Собираю данные…", "Collecting data…"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                DaemonMissingNotice()
            }
            Spacer()
        }
        .frame(minHeight: 140)
    }
}

/// The daemon is the whole engine, so its absence gets a real explanation and the
/// exact command, not a spinner that spins forever.
struct DaemonMissingNotice: View {
    private let command = "/Users/pavel/myProjects/MacFans/Scripts/install.sh"
    @State private var copied = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.system(size: 28))
                .foregroundStyle(Palette.warning)
            Text(L10n.t("Демон не запущен", "The daemon is not running"))
                .font(.headline)
            Text(L10n.t("Управлять вентиляторами может только процесс с правами root. Поставь его одной командой:",
                        "Only a root process can drive the fans. Install it with one command:"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            HStack(spacing: 8) {
                Text(command)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Button(copied ? L10n.t("Скопировано", "Copied") : L10n.t("Копировать", "Copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    copied = true
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
            .padding(10)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
        }
        .padding(.vertical, 18)
    }
}
