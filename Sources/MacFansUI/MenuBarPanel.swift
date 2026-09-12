import SwiftUI
import FanKit

/// The compact panel behind the menu bar item: state at a glance and the mode switch.
///
/// Unlike the window, this one takes the system's appearance as it finds it. Its
/// backing is the popover material macOS draws, which follows that appearance, so
/// pinning the panel to dark while the material went light left dark ink on a light
/// ground - or white ink on it, before the ink became semantic.
struct MenuBarPanel: View {
    @Environment(DaemonClient.self) private var client
    @Environment(DaemonInstaller.self) private var installer
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            header

            if client.isConnected {
                fanRow
                modeSwitch
                hottestSensors
                Divider().overlay(Palette.ink.opacity(0.09))
            } else {
                notRunning
            }

            HStack(spacing: 8) {
                Button(L10n.t("Открыть окно", "Open window")) { openWindow(id: "main") }
                    .buttonStyle(.glassProminent)
                    .frame(maxWidth: .infinity)
                Button(L10n.t("Выйти", "Quit")) { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.glass)
                    .frame(width: 84)
            }
        }
        .padding(16)
        .frame(width: 336)
    }

    private var header: some View {
        HStack {
            Text("MacFans").font(.system(size: 14, weight: .semibold))
            Spacer()
            HStack(spacing: 6) {
                LiveDot(active: client.isConnected)
                Text(client.isConnected ? L10n.t("на связи", "connected")
                                        : L10n.t("нет связи", "offline"))
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.ink.opacity(0.45))
            }
        }
    }

    private var fanRow: some View {
        HStack(spacing: 12) {
            ForEach(client.snapshot?.fans ?? []) { fan in
                HStack(spacing: 11) {
                    FanDial(rpm: fan.actualRPM, limits: fan.limits, controlled: fan.forced,
                            alert: fan.emergency || fan.writeError != nil,
                            size: 40, showsCaption: false, showsValue: false)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(L10n.t("Вент. \(fan.index + 1)", "Fan \(fan.index + 1)"))
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.ink.opacity(0.5))
                        Text(Format.rpm(fan.actualRPM))
                            .font(.system(size: 17, weight: .semibold))
                            .monospacedDigit()
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Palette.ink.opacity(0.07))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Palette.ink.opacity(0.12), lineWidth: 0.5))
                )
            }
        }
    }

    /// Switches every fan at once - the panel is for a quick decision, not per-fan work.
    private var modeSwitch: some View {
        let current = Binding<FanMode>(
            get: { client.config?.fans.first?.mode ?? .auto },
            set: { newMode in
                guard var config = client.draftConfig ?? client.snapshot?.config else { return }
                for index in config.fans.indices { config.fans[index].mode = newMode }
                client.draftConfig = config
                client.commit()
            }
        )
        return GlassSegmented(
            items: [
                .init(value: FanMode.auto, title: L10n.t("Авто", "Auto")),
                .init(value: FanMode.fixed, title: L10n.t("Фикс", "Fixed")),
                .init(value: FanMode.curve, title: L10n.t("Кривая", "Curve")),
            ],
            selection: current,
            segmentWidth: 84,
            fontSize: 11.5
        )
    }

    private var hottestSensors: some View {
        VStack(spacing: 8) {
            ForEach(topSensors) { sensor in
                HStack(spacing: 10) {
                    Text(SensorCatalog.info(for: sensor.key).name)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.ink.opacity(0.75))
                        .frame(width: 124, alignment: .leading)
                        .lineLimit(1)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.ink.opacity(0.08))
                            Capsule()
                                .fill(sensor.value > 70 ? Palette.heat : Palette.calm)
                                .frame(width: max(geometry.size.width
                                                  * min(max((sensor.value - 20) / 80, 0), 1), 3))
                        }
                    }
                    .frame(height: 3)
                    Text(Format.temperature(sensor.value))
                        .font(.system(size: 11.5))
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }
            }
        }
    }

    private var topSensors: [SensorReading] {
        Array((client.snapshot?.sensors ?? []).sorted { $0.value > $1.value }.prefix(3))
    }

    private var notRunning: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t("Управление не установлено", "Fan control is not installed"))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Palette.heat)
            Text(L10n.t("Открой окно и нажми «Установить» — macOS спросит пароль.",
                        "Open the window and press Install; macOS will ask for your password."))
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.ink.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
