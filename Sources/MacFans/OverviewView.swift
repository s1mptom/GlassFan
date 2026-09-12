import SwiftUI
import Charts
import FanKit

struct OverviewView: View {
    @Environment(DaemonClient.self) private var client
    @State private var window: TimeWindow = .fifteen

    enum TimeWindow: Int, CaseIterable, Identifiable {
        case five = 300, fifteen = 900, thirty = 1800
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .five:    return L10n.t("5м", "5m")
            case .fifteen: return L10n.t("15м", "15m")
            case .thirty:  return L10n.t("30м", "30m")
            }
        }
    }

    private var trackedKeys: [String] {
        let keys = client.config?.trackedSensors ?? SensorCatalog.defaultTracked
        let available = Set((client.snapshot?.sensors ?? []).map(\.key))
        return Array(keys.filter(available.contains).prefix(4))
    }

    private var samples: [HistorySample] {
        let cutoff = Date().timeIntervalSince1970 - Double(window.rawValue)
        return Self.downsample(client.history.filter { $0.t >= cutoff }, to: 300)
    }

    /// A little air above and below the data, never anchored at zero: room temperature
    /// is not a meaningful floor for a temperature chart.
    static func domain(for points: [SeriesPoint]) -> ClosedRange<Double>? {
        guard let low = points.map(\.value).min(), let high = points.map(\.value).max()
        else { return nil }
        let padding = max((high - low) * 0.12, 2)
        return (low - padding)...(high + padding)
    }

    /// Swift Charts slows to a crawl on thousands of marks; the eye cannot use them either.
    static func downsample(_ samples: [HistorySample], to limit: Int) -> [HistorySample] {
        guard samples.count > limit, limit > 0 else { return samples }
        let stride = Int((Double(samples.count) / Double(limit)).rounded(.up))
        return samples.enumerated().compactMap { $0.offset % stride == 0 ? $0.element : nil }
    }

    var body: some View {
        if client.isConnected {
            content
        } else {
            DaemonMissingNotice()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            dials.riseIn(0.02)
            statsRow.riseIn(0.10)
            chart.riseIn(0.18)
        }
    }

    // MARK: Fans

    private var dials: some View {
        HStack(spacing: 18) {
            ForEach(client.snapshot?.fans ?? []) { fan in
                HStack(spacing: 20) {
                    FanDial(rpm: fan.actualRPM, limits: fan.limits, controlled: fan.forced)

                    VStack(alignment: .leading, spacing: 9) {
                        Text(L10n.t("Вентилятор \(fan.index + 1)", "Fan \(fan.index + 1)"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.92))

                        modeChip(fan)

                        Text(subtitle(for: fan))
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.34))
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
    }

    private func modeChip(_ fan: FanReading) -> some View {
        let controlled = fan.forced
        let label: String = {
            if fan.writeError != nil { return L10n.t("запись отклонена", "write refused") }
            switch fan.mode {
            case .auto:  return L10n.t("Система", "System")
            case .fixed: return L10n.t("Фиксировано", "Fixed")
            case .curve: return L10n.t("По кривой", "Curve")
            }
        }()

        return HStack(spacing: 7) {
            if controlled && fan.mode == .curve {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.calm)
            }
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(controlled ? Palette.calm : .white.opacity(0.66))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(controlled ? Palette.calm.opacity(0.16) : .white.opacity(0.07))
                .overlay(Capsule().strokeBorder(
                    controlled ? Palette.calm.opacity(0.32) : .white.opacity(0.14), lineWidth: 0.5))
        )
    }

    private func subtitle(for fan: FanReading) -> String {
        if fan.emergency { return L10n.t("аварийный режим", "emergency") }
        if let temp = fan.drivingTemp, fan.mode == .curve {
            return L10n.t("ведёт \(Format.temperature(temp))", "driven by \(Format.temperature(temp))")
        }
        return fan.mode == .auto ? L10n.t("автоматически", "automatic")
                                 : L10n.t("под управлением", "under control")
    }

    // MARK: Headline temperatures

    private var statsRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(headlineGroups.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(.white.opacity(0.1))
                        .frame(width: 0.5, height: 30)
                        .padding(.horizontal, 15)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(Format.temperature(item.1))
                        .font(.system(size: 25, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(heatColor(item.1))
                    Text(item.0)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.42))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            GlassSegmented(
                items: TimeWindow.allCases.map { .init(value: $0, title: $0.title) },
                selection: $window,
                segmentWidth: nil,
                fontSize: 11
            )
        }
        .padding(.horizontal, 30)
        .padding(.top, 26)
    }

    private var headlineGroups: [(String, Double)] {
        [SensorGroup.cpu, .gpu, .comfort, .storage, .battery].compactMap { group in
            guard let hottest = client.sensors(in: group).max(by: { $0.value < $1.value })
            else { return nil }
            return (group.shortTitle, hottest.value)
        }
    }

    /// Warm only where it means something; everything cool stays neutral so the hot
    /// number is the one that catches the eye.
    private func heatColor(_ temperature: Double) -> Color {
        switch temperature {
        case ..<70: return .white.opacity(0.92)
        case ..<85: return Palette.heat
        default:    return Palette.critical
        }
    }

    // MARK: Chart

    private var chart: some View {
        let names = trackedKeys.map { SensorCatalog.info(for: $0).name }
        let points = samples.flatMap { sample in
            trackedKeys.compactMap { key -> SeriesPoint? in
                guard let value = sample.temps[key] else { return nil }
                return SeriesPoint(date: Date(timeIntervalSince1970: sample.t),
                                   value: value,
                                   series: SensorCatalog.info(for: key).name)
            }
        }

        return VStack(alignment: .leading, spacing: 12) {
            if points.isEmpty {
                DataHint()
            } else {
                TimeChart(points: points, order: names, unit: "°C",
                          yDomain: Self.domain(for: points), areaUnderFirst: true) {
                    String(format: "%.0f°", $0)
                }
                ChartLegend(names: names,
                            values: trackedKeys.map { client.reading(for: $0) },
                            trailing: L10n.t("°C · последние \(window.title)", "°C · last \(window.title)")) {
                    Format.temperature($0)
                }
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 18)
        .padding(.bottom, 22)
    }
}

struct DataHint: View {
    var body: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L10n.t("Собираю данные…", "Collecting data…"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
        }
        .frame(minHeight: 180)
    }
}

/// The daemon is the whole engine, so its absence gets a real explanation and a button
/// that installs it, not a spinner that spins forever.
struct DaemonMissingNotice: View {
    @Environment(DaemonInstaller.self) private var installer

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "fan.badge.automatic")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.white.opacity(0.55))

            Text(L10n.t("Управление вентиляторами не установлено",
                        "Fan control is not installed yet"))
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white)

            Text(L10n.t("Крутить вентиляторы может только процесс с правами администратора. Приложение поставит его само — macOS спросит пароль.",
                        "Only a process with administrator rights can drive the fans. The app installs one itself; macOS will ask for your password."))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 430)
                .fixedSize(horizontal: false, vertical: true)

            switch installer.status {
            case .working:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L10n.t("Устанавливаю…", "Installing…"))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .frame(height: 32)

            case .failed(let message):
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.critical)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 430)
                installButton

            default:
                installButton
            }
        }
        .riseIn(0.05)
    }

    private var installButton: some View {
        Button(L10n.t("Установить", "Install")) { installer.install() }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .frame(height: 32)
    }
}
