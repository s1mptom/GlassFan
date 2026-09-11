import SwiftUI
import FanKit

struct SettingsView: View {
    @Environment(DaemonClient.self) private var client

    private func configBinding() -> Binding<AppConfig>? {
        guard let current = client.draftConfig ?? client.snapshot?.config else { return nil }
        return Binding(
            get: { client.draftConfig ?? current },
            set: { client.draftConfig = $0; client.commit() }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let config = configBinding() {
                    safetyCard(config)
                    samplingCard(config)
                }
                panicCard
                aboutCard
            }
            .padding(22)
        }
    }

    private func safetyCard(_ config: Binding<AppConfig>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.t("Безопасность", "Safety"), systemImage: "shield")
                .font(.headline)
            HStack {
                Text(L10n.t("Аварийный порог", "Emergency threshold"))
                Spacer()
                Text(Format.temperatureFine(config.wrappedValue.emergencyTemp)).monospacedDigit()
            }
            Slider(value: config.emergencyTemp, in: AppConfig.emergencyRange, step: 1)
            Text(L10n.t("Выше этой температуры кривая игнорируется и вентиляторы уходят на максимум.",
                        "Above this the curve is abandoned and the fans go to full speed."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .glassCard()
    }

    private func samplingCard(_ config: Binding<AppConfig>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.t("Опрос", "Sampling"), systemImage: "timer")
                .font(.headline)
            HStack {
                Text(L10n.t("Интервал", "Interval"))
                Spacer()
                Text(String(format: "%.2f c", config.wrappedValue.pollInterval)).monospacedDigit()
            }
            Slider(value: config.pollInterval, in: AppConfig.pollRange, step: 0.25)
        }
        .glassCard()
    }

    private var panicCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.t("Вернуть управление системе", "Hand control back"), systemImage: "arrow.uturn.backward")
                .font(.headline)
            Text(L10n.t("Переводит все вентиляторы в авто и сбрасывает режимы. Пригодится, если что-то пошло не так.",
                        "Puts every fan back on auto and clears the modes. For when something looks wrong."))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(L10n.t("Отпустить все вентиляторы", "Release all fans")) {
                client.releaseAll()
            }
            .buttonStyle(.glassProminent)
            .tint(Palette.critical)
        }
        .glassCard()
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(L10n.t("О программе", "About"), systemImage: "info.circle")
                .font(.headline)
            LabeledContent(L10n.t("Демон", "Daemon"),
                           value: client.snapshot?.daemonVersion ?? "—")
            LabeledContent(L10n.t("Датчиков найдено", "Sensors found"),
                           value: "\(client.snapshot?.sensors.count ?? 0)")
            LabeledContent(L10n.t("Вентиляторов", "Fans"),
                           value: "\(client.snapshot?.fans.count ?? 0)")
        }
        .glassCard()
    }
}
