import SwiftUI
import FanKit

@main
struct MacFansApp: App {
    @State private var client = DaemonClient()
    @State private var installer = DaemonInstaller()

    var body: some Scene {
        Window(L10n.t("MacFans", "MacFans"), id: "main") {
            MainWindow()
                .environment(client)
                .environment(installer)
                .task {
                    client.start()
                    installer.refresh()
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1060, height: 700)

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

enum Section: String, CaseIterable, Identifiable {
    case overview, fans, sensors, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return L10n.t("Обзор", "Overview")
        case .fans:     return L10n.t("Вентиляторы", "Fans")
        case .sensors:  return L10n.t("Датчики", "Sensors")
        case .settings: return L10n.t("Настройки", "Settings")
        }
    }
}

struct MainWindow: View {
    @Environment(DaemonClient.self) private var client
    // Lets a screenshot or a test open straight onto one screen.
    @State private var section: Section = Section(
        rawValue: ProcessInfo.processInfo.environment["MACFANS_TAB"] ?? "") ?? .overview

    var body: some View {
        ZStack {
            GlassBackground()
            content
        }
        .background(WindowConfigurator())
        .preferredColorScheme(.dark)
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch section {
                case .overview: OverviewView()
                case .fans:     FansView()
                case .sensors:  SensorsView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The window's own title bar is hidden, so this row carries the tabs and leaves
    /// room for the traffic lights on the left.
    private var header: some View {
        HStack(spacing: 20) {
            Color.clear.frame(width: 72, height: 1)

            Spacer(minLength: 0)

            GlassSegmented(
                items: Section.allCases.map { .init(value: $0, title: $0.title) },
                selection: $section,
                segmentWidth: 104
            )

            Spacer(minLength: 0)

            HStack(spacing: 7) {
                LiveDot(active: client.isConnected)
                Text(client.isConnected ? L10n.t("на связи", "connected")
                                        : L10n.t("нет связи", "offline"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
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
            .onAppear {
                withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                    breathing = true
                }
            }
    }
}
