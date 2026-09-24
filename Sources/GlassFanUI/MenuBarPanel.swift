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
                if client.snapshot?.fans.isEmpty == false {
                    fanRow
                    modeSwitch
                }
                sensorSummary
                Divider().overlay(Palette.ink.opacity(0.09))
            } else {
                notRunning
            }

            // The widths go on the labels, not on the buttons: a frame outside a
            // glass button widens the space it sits in and leaves the button its
            // natural size, floating off-centre in it.
            HStack(spacing: 8) {
                Button {
                    MainWindowOpener.open(using: openWindow)
                } label: {
                    Text(L10n.t("Открыть окно", "Open window"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Text(L10n.t("Выйти", "Quit"))
                        .frame(width: 92 - 24)
                }
                .buttonStyle(.glass)
            }
        }
        .padding(16)
        .frame(width: 336)
        // While this is open it is the one thing looking at the full reading, which is
        // otherwise held back whenever the window cannot be seen.
        .onAppear { client.panelIsOpen = true }
        .onDisappear { client.panelIsOpen = false }
    }

    private var header: some View {
        HStack {
            Text("GlassFan").font(.system(size: 14, weight: .semibold))
            Spacer()
            ConnectionStatus(fontSize: 11, opacity: 0.45)
        }
    }

    private var fanRow: some View {
        HStack(spacing: 12) {
            ForEach(client.snapshot?.fans ?? []) { fan in
                HStack(spacing: 11) {
                    FanDial(rpm: fan.actualRPM, limits: fan.limits, controlled: fan.forced,
                            alert: fan.alerting,
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
            segmentWidth: nil,
            fontSize: 11.5,
            fills: true
        )
    }

    private var sensorSummary: some View {
        VStack(spacing: 8) {
            ForEach(headlines, id: \.0) { group, value in
                HStack(spacing: 10) {
                    Text(group.shortTitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.ink.opacity(0.75))
                        .frame(width: 128, alignment: .leading)
                        .lineLimit(1)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.ink.opacity(0.08))
                        Capsule()
                            .fill(value > 70 ? Palette.heat : Palette.calm)
                            .scaleEffect(x: max(min(max((value - 20) / 80, 0), 1), 0.01),
                                         y: 1, anchor: .leading)
                    }
                    .frame(height: 3)
                    Text(Format.temperatureFine(value).replacingOccurrences(of: " °C", with: "°"))
                        .font(.system(size: 11.5))
                        .monospacedDigit()
                        .frame(width: 46, alignment: .trailing)
                }
            }
        }
    }

    /// The same three rows every time, in the same places: the hottest three
    /// sensors of the moment swapped places and names as the machine worked, and
    /// often all three were cores of one CPU saying the same thing.
    private var headlines: [(SensorGroup, Double)] {
        SensorCatalog.headlines(client.snapshot?.sensors ?? [], groups: [.cpu, .gpu, .storage])
    }

    private var notRunning: some View {
        DaemonAbsenceReader { absence in
            VStack(alignment: .leading, spacing: 10) {
                Text(absence.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(absence.isTransient ? Palette.ink.opacity(0.85) : Palette.heat)
                Text(hint(for: absence))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.ink.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func hint(for absence: DaemonAbsence) -> String {
        switch absence {
        case .working, .connecting:
            return L10n.t("Через пару секунд всё вернётся.", "Back in a couple of seconds.")
        case .silent:
            return L10n.t("Открой окно и нажми «Переустановить» — macOS спросит пароль.",
                          "Open the window and press Reinstall; macOS will ask for your password.")
        case .notInstalled, .failed:
            return L10n.t("Открой окно и нажми «Установить» — macOS спросит пароль.",
                          "Open the window and press Install; macOS will ask for your password.")
        }
    }
}

/// Brings the main window in front of whatever the user is doing.
///
/// `openWindow` alone was the whole of the menu bar's "Open window", and pressing
/// it did nothing anyone could see except turn the panel grey. The press landed
/// and the window was ordered in - taking key from the panel, hence the grey -
/// but a menu bar panel does not activate its app, so the window came forward
/// inside an app that was behind everything else: behind the frontmost app, or
/// on the Space it was last on. The window's own activation only runs the first
/// time it appears.
///
/// So everything that can leave it out of sight is handled: the panel is put
/// away, the app is activated, the window is pulled to this Space, brought back
/// onto a screen if it is off all of them, and ordered front regardless.
@MainActor
enum MainWindowOpener {
    static func open(using openWindow: OpenWindowAction) {
        let panel = NSApp.keyWindow
        DockPresence.windowOpening()
        NSApp.activate()
        openWindow(id: "main")
        DispatchQueue.main.async {
            guard let window = mainWindow() else { return }
            if let panel, panel !== window { panel.orderOut(nil) }
            window.collectionBehavior.insert(.moveToActiveSpace)
            if window.isMiniaturized { window.deminiaturize(nil) }
            if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) {
                window.center()
            }
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    private static func mainWindow() -> NSWindow? {
        NSApp.windows.first { $0.canBecomeMain && $0.styleMask.contains(.titled) }
    }

    /// What the window and the app look like right now, for the reopen hook.
    static func describe() -> String {
        let main = NSApp.windows.first { $0.canBecomeMain && $0.styleMask.contains(.titled) }
        return "appActive=\(NSApp.isActive) window=\(main == nil ? "none" : "present") "
            + "visible=\(main?.isVisible ?? false) key=\(main?.isKeyWindow ?? false) "
            + "onScreen=\(main?.occlusionState.contains(.visible) ?? false) "
            + "frontmostApp=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")"
    }
}

