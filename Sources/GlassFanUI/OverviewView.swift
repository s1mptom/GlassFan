import SwiftUI
import Charts
import FanKit

struct OverviewView: View {
    @Environment(DaemonClient.self) private var client
    @State private var window: TimeWindow = .fifteen
    @AppStorage(Screen.storageKey) private var screen: Screen = .overview
    @AppStorage(FansView.selectedKey) private var selectedFan: Int = 0

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

    /// As many as the palette has distinct, validated steps for. Past that a series
    /// would have to reuse a colour, and two lines the same colour is worse than a
    /// line not drawn - so the extras are left off and said out loud instead.
    private var chartableKeys: [String] {
        let keys = client.config?.trackedSensors ?? SensorCatalog.defaultTracked
        let available = Set((client.snapshot?.sensors ?? []).map(\.key))
        return keys.filter(available.contains)
    }

    private var trackedKeys: [String] {
        Array(chartableKeys.prefix(Palette.series.count))
    }

    private var overflowCount: Int {
        max(chartableKeys.count - Palette.series.count, 0)
    }

    /// Three hundred was more marks than the plot has pixels to tell apart, and
    /// Swift Charts pays for every one of them: four series over three hundred
    /// samples is twelve hundred line marks rebuilt on every reading. At this
    /// width the curves are indistinguishable.
    private static let sampleLimit = 180

    private var samples: [HistorySample] {
        ChartSampling.bucketed(client.history,
                               window: Double(window.rawValue),
                               now: Date().timeIntervalSince1970,
                               limit: Self.sampleLimit)
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
            if client.snapshot?.fans.isEmpty == false {
                dials.riseIn(0.02)
            } else if client.snapshot != nil {
                // No fans to draw - a MacBook Air. Said once, quietly, instead of an
                // empty row where the dials would be.
                Text(L10n.t("Пассивное охлаждение — в этом Mac нет вентиляторов",
                            "Passive cooling - this Mac has no fans"))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink.opacity(0.4))
                    .padding(.horizontal, 30)
                    .padding(.top, 22)
                    .riseIn(0.02)
            }
            statsRow.riseIn(0.10)
            chart.riseIn(0.18)
        }
    }

    // MARK: Fans

    private var dials: some View {
        HStack(spacing: 18) {
            ForEach(client.snapshot?.fans ?? []) { fan in
                HStack(spacing: 20) {
                    FanDial(rpm: fan.actualRPM, limits: fan.limits, controlled: fan.forced,
                            alert: fan.emergency || fan.writeError != nil)

                    VStack(alignment: .leading, spacing: 9) {
                        Text(L10n.t("Вентилятор \(fan.index + 1)", "Fan \(fan.index + 1)"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Palette.ink.opacity(0.92))

                        modeChip(fan)

                        Text(subtitle(for: fan))
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.ink.opacity(0.34))
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
        let refused = fan.writeError != nil
        let controlled = fan.forced
        let label: String = {
            if refused { return L10n.t("запись отклонена", "write refused") }
            switch fan.mode {
            case .auto:  return L10n.t("Система", "System")
            case .fixed: return L10n.t("Фиксировано", "Fixed")
            case .curve: return L10n.t("По кривой", "Curve")
            }
        }()

        // A refused write is the app failing at its one job, so it gets the alarm
        // colour rather than the same grey a fan on auto gets.
        let accent: Color = refused ? Palette.critical
                                    : controlled ? Palette.calm : Palette.ink.opacity(0.66)

        // The chip is the way into that fan's settings: one click lands on the
        // Fans screen with this fan already selected.
        return Button {
            selectedFan = fan.index
            screen = .fans
        } label: {
          HStack(spacing: 7) {
            if refused {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Palette.critical)
            } else if controlled && fan.mode == .curve {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.calm)
            }
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(refused ? Palette.critical.opacity(0.14)
                           : controlled ? Palette.calm.opacity(0.16) : Palette.ink.opacity(0.07))
                .overlay(Capsule().strokeBorder(
                    refused ? Palette.critical.opacity(0.35)
                    : controlled ? Palette.calm.opacity(0.32) : Palette.ink.opacity(0.14),
                    lineWidth: 0.5))
          )
          .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(L10n.t("Открыть настройки вентилятора", "Open this fan's settings"))
    }

    private func subtitle(for fan: FanReading) -> String {
        if fan.emergency { return L10n.t("аварийный режим", "emergency") }
        // Without this the fan reads "write refused" and "under control" at once.
        if fan.writeError != nil { return L10n.t("настройка не применилась", "the setting did not take") }
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
                        .fill(Palette.ink.opacity(0.1))
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
                        .foregroundStyle(Palette.ink.opacity(0.42))
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

    /// One walk over the readings, and each group speaks through its named parts:
    /// the hottest core, GPU cluster or drive, never a probe alias running warm.
    private var headlineGroups: [(String, Double)] {
        SensorCatalog.headlines(client.snapshot?.sensors ?? [],
                                groups: [.cpu, .gpu, .comfort, .storage, .battery])
            .map { ($0.0.shortTitle, $0.1) }
    }

    private var legendTrailing: String {
        let window = L10n.t("°C · последние \(self.window.title)", "°C · last \(self.window.title)")
        guard overflowCount > 0 else { return window }
        return L10n.t("\(window) · ещё \(overflowCount) не поместилось",
                      "\(window) · \(overflowCount) more won't fit")
    }

    /// Warm only where it means something; everything cool stays neutral so the hot
    /// number is the one that catches the eye.
    private func heatColor(_ temperature: Double) -> Color {
        switch temperature {
        case ..<70: return Palette.ink.opacity(0.92)
        case ..<85: return Palette.heat
        default:    return Palette.critical
        }
    }

    // MARK: Chart

    private var chart: some View {
        let names = SensorCatalog.distinctNames(for: trackedKeys)
        let points = ChartSampling.points(
            samples, keys: trackedKeys,
            gap: ChartSampling.breakGap(window: Double(window.rawValue), limit: Self.sampleLimit,
                                        pollInterval: client.config?.pollInterval ?? 1))

        return VStack(alignment: .leading, spacing: 12) {
            if points.isEmpty {
                DataHint()
            } else {
                TimeChart(points: points, order: trackedKeys, labels: names, unit: "°C",
                          yDomain: ChartSampling.domain(for: points.map(\.value)), areaUnderFirst: true) {
                    String(format: "%.0f°", $0)
                }
                ChartLegend(names: names,
                            values: trackedKeys.map { client.reading(for: $0) },
                            trailing: legendTrailing) {
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
                    .foregroundStyle(Palette.ink.opacity(0.45))
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
                .foregroundStyle(Palette.ink.opacity(0.55))

            Text(L10n.t("Управление вентиляторами не установлено",
                        "Fan control is not installed yet"))
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Palette.ink)

            Text(L10n.t("Крутить вентиляторы может только процесс с правами администратора. Приложение поставит его само — macOS спросит пароль.",
                        "Only a process with administrator rights can drive the fans. The app installs one itself; macOS will ask for your password."))
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink.opacity(0.45))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 430)
                .fixedSize(horizontal: false, vertical: true)

            switch installer.status {
            case .working:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L10n.t("Устанавливаю…", "Installing…"))
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.ink.opacity(0.6))
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
