import SwiftUI
import FanKit

struct SettingsView: View {
    @Environment(DaemonClient.self) private var client
    @Environment(DaemonInstaller.self) private var installer
    @AppStorage(GlassStyle.frostKey) private var frost = GlassStyle.defaultFrost
    @AppStorage(GlassStyle.tintKey) private var tint = GlassStyle.defaultTint

    private func configBinding() -> Binding<AppConfig>? {
        guard let current = client.draftConfig ?? client.snapshot?.config else { return nil }
        return Binding(
            get: { client.draftConfig ?? current },
            set: { client.draftConfig = $0; client.commit() }
        )
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 30, alignment: .topLeading),
                                GridItem(.flexible(), alignment: .topLeading)],
                      alignment: .leading, spacing: 30) {
                if let config = configBinding() {
                    safety(config).riseIn(0.02)
                } else {
                    daemonMissing.riseIn(0.02)
                }
                glass.riseIn(0.08)
                daemon.riseIn(0.14)
                panic.riseIn(0.20)
            }
            .padding(.horizontal, 30)
            .padding(.top, 22)
            .padding(.bottom, 26)
        }
        .scrollContentBackground(.hidden)
    }

    private func safety(_ config: Binding<AppConfig>) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionCaption(text: L10n.t("Безопасность", "Safety"))
            LabelledSlider(
                title: L10n.t("Аварийный порог", "Emergency threshold"),
                valueText: Format.temperatureFine(config.wrappedValue.emergencyTemp),
                value: config.emergencyTemp,
                range: AppConfig.emergencyRange,
                step: 1,
                footnote: L10n.t("Выше этой температуры кривая игнорируется и вентиляторы уходят на максимум.",
                                 "Above this the curve is abandoned and the fans go to full speed."),
                tint: Palette.heat
            )
            LabelledSlider(
                title: L10n.t("Интервал опроса", "Sampling interval"),
                valueText: String(format: L10n.t("%.2f с", "%.2f s"),
                                  config.wrappedValue.pollInterval),
                value: config.pollInterval,
                range: AppConfig.pollRange,
                step: 0.25
            )
        }
    }

    private var daemonMissing: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionCaption(text: L10n.t("Безопасность", "Safety"))
            Text(L10n.t("Настройки появятся, когда демон будет установлен.",
                        "These appear once the daemon is installed."))
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink.opacity(0.4))
        }
    }

    private var isDefaultGlass: Bool {
        abs(frost - GlassStyle.defaultFrost) < 0.001 && abs(tint - GlassStyle.defaultTint) < 0.001
    }

    private var glass: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                SectionCaption(text: L10n.t("Стекло", "Glass"))
                Spacer()
                // Only offered once the dials have actually been moved: a reset that is
                // always there invites a press that does nothing.
                if !isDefaultGlass {
                    Button(L10n.t("Сбросить", "Reset")) {
                        withAnimation(.easeOut(duration: 0.25)) {
                            frost = GlassStyle.defaultFrost
                            tint = GlassStyle.defaultTint
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.calm)
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: isDefaultGlass)
            LabelledSlider(
                title: L10n.t("Матовость", "Frost"),
                valueText: "\(Int(frost * 100)) %",
                value: $frost, range: GlassStyle.frostRange, step: nil
            )
            LabelledSlider(
                title: L10n.t("Тон", "Tone"),
                valueText: tint == 0 ? L10n.t("ровно", "neutral") : String(format: "%+.0f %%", tint * 100),
                value: $tint, range: GlassStyle.tintRange, step: nil,
                footnote: L10n.t("Регулирует подложку окна. Карточки всегда прозрачные.",
                                 "Adjusts the window backing. The cards stay clear.")
            )
        }
    }

    private var daemon: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionCaption(text: L10n.t("Управление вентиляторами", "Fan control"))
            switch installer.status {
            case .installed:
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(red: 0.20, green: 0.79, blue: 0.54))
                    Text(L10n.t("Установлено · запускается вместе с системой",
                                "Installed · starts with the system"))
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.ink.opacity(0.88))
                }
                HStack(spacing: 10) {
                    Button(L10n.t("Переустановить", "Reinstall")) { installer.install() }
                        .buttonStyle(.glass)
                    Button(L10n.t("Удалить", "Remove")) { installer.uninstall() }
                        .buttonStyle(.glass)
                }
            case .working:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L10n.t("Выполняю…", "Working…"))
                        .font(.system(size: 12)).foregroundStyle(Palette.ink.opacity(0.6))
                }
            case .failed(let message):
                Text(message).font(.system(size: 11.5)).foregroundStyle(Palette.critical)
                Button(L10n.t("Повторить", "Try again")) { installer.install() }
                    .buttonStyle(.glassProminent)
            case .notInstalled:
                Text(L10n.t("Не установлено. Без этого приложение только показывает температуры.",
                            "Not installed. Without it the app only shows temperatures."))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
                Button(L10n.t("Установить", "Install")) { installer.install() }
                    .buttonStyle(.glassProminent)
            }
        }
    }

    private var panic: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionCaption(text: L10n.t("Если что-то пошло не так", "If something looks wrong"))
            Text(L10n.t("Переводит все вентиляторы в авто и сбрасывает режимы — управление возвращается системе.",
                        "Puts every fan back on auto and clears the modes; the system takes over."))
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.ink.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)
            Button {
                client.releaseAll()
            } label: {
                Label(L10n.t("Отпустить все вентиляторы", "Release all fans"),
                      systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.glassProminent)
            .tint(Palette.critical)

            HStack(spacing: 22) {
                Text(L10n.t("Демон \(client.snapshot?.daemonVersion ?? "—")",
                            "Daemon \(client.snapshot?.daemonVersion ?? "—")"))
                Text(L10n.t("\(client.snapshot?.sensors.count ?? 0) датчиков",
                            "\(client.snapshot?.sensors.count ?? 0) sensors"))
                Text(L10n.t("\(client.snapshot?.fans.count ?? 0) вентилятора",
                            "\(client.snapshot?.fans.count ?? 0) fans"))
            }
            .font(.system(size: 11))
            .foregroundStyle(Palette.ink.opacity(0.28))
            .padding(.top, 6)
        }
    }
}
