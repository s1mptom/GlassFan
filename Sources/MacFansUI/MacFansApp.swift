import SwiftUI
import FanKit

public struct MacFansApp: App {
    @State private var client = DaemonClient()
    @State private var installer = DaemonInstaller()

    public init() {
        // Lets a screenshot or a test open straight onto one screen, by seeding the
        // same stored value the window restores from.
        if let tab = ProcessInfo.processInfo.environment["MACFANS_TAB"],
           Screen(rawValue: tab) != nil {
            UserDefaults.standard.set(tab, forKey: Screen.storageKey)
        }
    }

    public var body: some Scene {
        Window(L10n.t("MacFans", "MacFans"), id: "main") {
            MainWindow()
                .frame(minWidth: 900, minHeight: 600)
                .environment(client)
                .environment(installer)
                .task {
                    client.start()
                    installer.refresh()
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .commands {
            CommandGroup(before: .toolbar) {
                ScreenCommands()
                Divider()
            }
        }
        .windowStyle(.hiddenTitleBar)
        // The window in the design is 1008x640; the 1120x720 artboard around it is
        // the desktop it was drawn floating on.
        .defaultSize(width: 1008, height: 640)
        // Below this the fan sidebar and the detail pane start colliding and the
        // headline row runs out of room, so the window simply refuses to go there.
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarPanel()
                .environment(client)
                .environment(installer)
        } label: {
            MenuBarLabel()
                .environment(client)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The strip in the menu bar: hottest sensor and the faster fan, nothing else.
struct MenuBarLabel: View {
    @Environment(DaemonClient.self) private var client

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: client.isConnected ? "fan" : "exclamationmark.triangle")
            if let hottest = client.hottest {
                Text(Format.temperature(hottest.value))
            }
            if let fastest = client.snapshot?.fans.map(\.actualRPM).max(), fastest > 0 {
                Text(Format.rpm(fastest)).foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
    }
}

/// Named `Screen` rather than `Section` so it does not shadow `SwiftUI.Section`,
/// which forced fully qualified names at every use of the real one.
enum Screen: String, CaseIterable, Identifiable {
    case overview, fans, sensors, settings
    var id: String { rawValue }

    static let storageKey = "screen"

    var title: String {
        switch self {
        case .overview: return L10n.t("Обзор", "Overview")
        case .fans:     return L10n.t("Вентиляторы", "Fans")
        case .sensors:  return L10n.t("Датчики", "Sensors")
        case .settings: return L10n.t("Настройки", "Settings")
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.50percent"
        case .fans:     return "fan"
        case .sensors:  return "thermometer.medium"
        case .settings: return "slider.horizontal.3"
        }
    }
}

/// The View menu, which is also what gives the tabs their Command-1..4 shortcuts.
/// It reaches the window through the same stored value the window itself binds to,
/// so the menu and the segmented control can never disagree.
struct ScreenCommands: View {
    @AppStorage(Screen.storageKey) private var screen: Screen = .overview

    var body: some View {
        ForEach(Array(Screen.allCases.enumerated()), id: \.element) { index, item in
            Button {
                screen = item
            } label: {
                Label(item.title, systemImage: item.symbol)
            }
            .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
        }
    }
}

struct MainWindow: View {
    @Environment(DaemonClient.self) private var client
    @AppStorage(GlassStyle.frostKey) private var frost = GlassStyle.defaultFrost
    /// The scheme follows the tone alone: the frosting is lightness-neutral, so
    /// it cannot change which way the ink has to go.
    @AppStorage(GlassStyle.tintKey) private var tint = GlassStyle.defaultTint
    /// Remembered between launches, so the app reopens where it was left.
    @AppStorage(Screen.storageKey) private var screen: Screen = .overview

    private var scheme: ColorScheme {
        GlassStyle.isLight(tint: tint) ? .light : .dark
    }

    var body: some View {
        ZStack {
            GlassBackground()
            content
        }
        .background(WindowConfigurator(blurRadius: WindowBlur.radius(for: frost)))
        // Both, and they do different jobs. `preferredColorScheme` travels up to the
        // window and settles its chrome; only writing the environment value settles
        // the scheme the content is drawn against, which is what decides where
        // `Palette.ink` lands. With just the former the backing goes light and the
        // text stays white on it.
        .environment(\.colorScheme, scheme)
        .preferredColorScheme(scheme)
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch screen {
                case .overview: OverviewView()
                case .fans:     FansView()
                case .sensors:  SensorsView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The outgoing screen used to vanish on the same frame the selector
            // started moving. It fades instead, so the selector's glide and the
            // change of content read as one movement. Short: the incoming screen
            // has its own entrance to get on with.
            .id(screen)
            .transition(.opacity.animation(.easeInOut(duration: 0.16)))
        }
    }

    /// The window's own title bar is hidden, so this row carries the tabs and leaves
    /// room for the traffic lights on the left.
    private var header: some View {
        HStack(spacing: 20) {
            Color.clear.frame(width: 72, height: 1)

            Spacer(minLength: 0)

            GlassSegmented(
                items: Screen.allCases.map { .init(value: $0, title: $0.title) },
                selection: $screen,
                segmentWidth: nil
            )

            Spacer(minLength: 0)

            HStack(spacing: 7) {
                LiveDot(active: client.isConnected)
                Text(client.isConnected ? L10n.t("на связи", "connected")
                                        : L10n.t("нет связи", "offline"))
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.ink.opacity(0.45))
            }
            .frame(width: 96, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }
}

/// Slow pulse, so a live connection reads as alive without blinking at anyone.
struct LiveDot: View {
    let active: Bool
    @State private var breathing = false

    var body: some View {
        Circle()
            .fill(active ? Color(red: 0.20, green: 0.79, blue: 0.54) : Palette.critical)
            .frame(width: 6, height: 6)
            .shadow(color: (active ? Color(red: 0.20, green: 0.79, blue: 0.54) : Palette.critical)
                .opacity(0.9), radius: 5)
            .opacity(breathing ? 1 : 0.5)
            // The word beside it already says "connected"; the dot is decoration.
            .accessibilityHidden(true)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                    breathing = true
                }
            }
    }
}
