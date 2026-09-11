import SwiftUI
import FanKit

/// The compact panel behind the menu bar item: state at a glance and the mode switch.
struct MenuBarPanel: View {
    @Environment(DaemonClient.self) private var client
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                header

                if client.isConnected {
                    ForEach(client.snapshot?.fans ?? []) { fan in
                        fanRow(fan)
                    }
                    Divider().opacity(0.4)
                    hottestSensors
                } else {
                    Text(client.lastError ?? L10n.t("Демон не запущен", "Daemon is not running"))
                        .font(.callout)
                        .foregroundStyle(Palette.critical)
                    Text(L10n.t("Запусти Scripts/install.sh, чтобы поставить демона.",
                                "Run Scripts/install.sh to install the daemon."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button(L10n.t("Открыть окно", "Open window")) { openWindow(id: "main") }
                        .buttonStyle(.glassProminent)
                    Spacer()
                    Button(L10n.t("Выйти", "Quit")) { NSApplication.shared.terminate(nil) }
                        .buttonStyle(.glass)
                }
            }
            .padding(16)
            .frame(width: 320)
        }
    }

    private var header: some View {
        HStack {
            Label("MacFans", systemImage: "fan.fill").font(.headline)
            Spacer()
            if let hottest = client.hottest {
                Text(Format.temperatureFine(hottest.value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func fanRow(_ fan: FanReading) -> some View {
        let binding = Binding<FanMode>(
            get: { client.config?.fans.first { $0.id == fan.index }?.mode ?? .auto },
            set: { newMode in
                guard var config = client.draftConfig ?? client.snapshot?.config,
                      let index = config.fans.firstIndex(where: { $0.id == fan.index }) else { return }
                config.fans[index].mode = newMode
                client.draftConfig = config
                client.commit()
            }
        )

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.t("Вентилятор \(fan.index + 1)", "Fan \(fan.index + 1)"))
                    .font(.subheadline)
                Spacer()
                Text(Format.rpm(fan.actualRPM) + " rpm")
                    .monospacedDigit()
                    .font(.subheadline.weight(.medium))
            }
            Picker("", selection: binding) {
                Text(L10n.t("Авто", "Auto")).tag(FanMode.auto)
                Text(L10n.t("Фикс", "Fixed")).tag(FanMode.fixed)
                Text(L10n.t("Кривая", "Curve")).tag(FanMode.curve)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var hottestSensors: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(topSensors, id: \.key) { sensor in
                HStack {
                    Text(SensorCatalog.info(for: sensor.key).name)
                        .font(.caption)
                    Spacer()
                    Text(Format.temperatureFine(sensor.value))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var topSensors: [SensorReading] {
        Array((client.snapshot?.sensors ?? []).sorted { $0.value > $1.value }.prefix(3))
    }
}
