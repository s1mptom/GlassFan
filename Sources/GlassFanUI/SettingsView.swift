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

    /// Four cards filling the window two by two. Should they ever outgrow it - a
    /// long message from the installer, a smaller window - the same grid scrolls.
    var body: some View {
        ViewThatFits(in: .vertical) {
            grid(filling: true)
            ScrollView {
                grid(filling: false)
            }
            .scrollContentBackground(.hidden)
        }
        .padding(.horizontal, Metrics.page)
        .padding(.top, Metrics.gap)
        .padding(.bottom, Metrics.page)
    }

    private func grid(filling: Bool) -> some View {
        VStack(spacing: Metrics.gap) {
            row(filling: filling) {
                Group {
                    if let config = configBinding() {
                        safety(config)
                    } else {
                        daemonMissing
                    }
                }
                .settingsCard().riseIn(0.02)
                glass.settingsCard().riseIn(0.08)
            }
            row(filling: filling) {
                daemon.settingsCard().riseIn(0.14)
                panic.settingsCard().riseIn(0.20)
            }
        }
    }

    /// Two cards side by side, as tall as each other: sharing the window's height
    /// when filling it, as tall as the taller one's content when scrolling.
    private func row(filling: Bool, @ViewBuilder _ cards: () -> some View) -> some View {
        HStack(alignment: .top, spacing: Metrics.gap) { cards() }
            .fixedSize(horizontal: false, vertical: !filling)
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
                .foregroundStyle(Palette.ink.opacity(0.5))
        }
    }

    private var isDefaultGlass: Bool {
        abs(frost - GlassStyle.defaultFrost) < 0.001 && abs(tint - GlassStyle.defaultTint) < 0.001
    }

    private var glass: some View {
        VStack(alignment: .leading, spacing: 18) {
            // The reset rides over the caption's row rather than in it, so its taller
            // type does not push this card's content below the one beside it.
            SectionCaption(text: L10n.t("Стекло", "Glass"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .trailing) {
                    // Only offered once the dials have actually been moved: a reset that
                    // is always there invites a press that does nothing.
                    if !isDefaultGlass {
                        Button(L10n.t("Сбросить", "Reset")) {
                            withAnimation(.easeOut(duration: 0.25)) {
                                frost = GlassStyle.defaultFrost
                                tint = GlassStyle.defaultTint
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
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
            case .outdated:
                HStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .foregroundStyle(Palette.heat)
                    Text(L10n.t("Установлен старый демон · в приложении новее",
                                "An older daemon is installed · this app carries a newer one"))
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.ink.opacity(0.88))
                }
                Text(L10n.t("Логика управления живёт в демоне, так что без обновления новые возможности не действуют.",
                            "The control logic lives in the daemon, so until it is updated the new behaviour does not apply."))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                Button(L10n.t("Обновить", "Update")) { installer.install() }
                    .buttonStyle(.glassProminent)
            case .working:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L10n.t("Выполняю…", "Working…"))
                        .font(.system(size: 12)).foregroundStyle(Palette.ink.opacity(0.6))
                }
            case .failed(let message):
                Text(message).font(.system(size: 12)).foregroundStyle(Palette.critical)
                Button(L10n.t("Повторить", "Try again")) { installer.install() }
                    .buttonStyle(.glassProminent)
            case .notInstalled:
                Text(L10n.t("Не установлено. Без этого приложение только показывает температуры.",
                            "Not installed. Without it the app only shows temperatures."))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                Button(L10n.t("Установить", "Install")) { installer.install() }
                    .buttonStyle(.glassProminent)
            }
            Spacer(minLength: 0)
            HStack(spacing: 16) {
                Text(L10n.t("Демон \(client.snapshot?.daemonVersion ?? "—")",
                            "Daemon \(client.snapshot?.daemonVersion ?? "—")"))
                Text(L10n.t("\(client.snapshot?.sensors.count ?? 0) датчиков",
                            "\(client.snapshot?.sensors.count ?? 0) sensors"))
                Text(L10n.t("\(client.snapshot?.fans.count ?? 0) вентилятора",
                            "\(client.snapshot?.fans.count ?? 0) fans"))
            }
            .font(.system(size: 12))
            .monospacedDigit()
            .foregroundStyle(Palette.ink.opacity(0.5))
        }
    }

    private var panic: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionCaption(text: L10n.t("Если что-то пошло не так", "If something looks wrong"))
            Text(L10n.t("Переводит все вентиляторы в авто и сбрасывает режимы — управление возвращается системе.",
                        "Puts every fan back on auto and clears the modes; the system takes over."))
                .font(.system(size: 13))
                .foregroundStyle(Palette.ink.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
            Button {
                client.releaseAll()
            } label: {
                Label(L10n.t("Отпустить все вентиляторы", "Release all fans"),
                      systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.glassProminent)
            .tint(Palette.critical)
        }
    }
}

private extension View {
    /// A settings section: content from the top-left, as tall as its row.
    func settingsCard() -> some View {
        self.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .card()
    }
}
