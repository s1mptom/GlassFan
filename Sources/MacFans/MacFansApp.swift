import SwiftUI
import FanKit

@main
struct MacFansApp: App {
    @State private var client = DaemonClient()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window(L10n.t("MacFans", "MacFans"), id: "main") {
            MainWindow()
                .environment(client)
                .containerBackground(for: .window) { GlassBackground() }
                .task {
                    client.start()
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1080, height: 780)

        MenuBarExtra {
            MenuBarPanel()
                .environment(client)
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
                Text(Format.rpm(fastest))
                    .foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
    }
}

enum Section: String, CaseIterable, Identifiable {
    case dashboard, fans, sensors, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return L10n.t("Обзор", "Overview")
        case .fans: return L10n.t("Вентиляторы", "Fans")
        case .sensors: return L10n.t("Датчики", "Sensors")
        case .settings: return L10n.t("Настройки", "Settings")
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: return "chart.xyaxis.line"
        case .fans: return "fan"
        case .sensors: return "thermometer.medium"
        case .settings: return "gearshape"
        }
    }
}

struct MainWindow: View {
    @Environment(DaemonClient.self) private var client
    @State private var section: Section = .dashboard

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $section) { item in
                Label(item.title, systemImage: item.symbol).tag(item)
            }
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .bottom) {
                ConnectionBadge()
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
        } detail: {
            Group {
                switch section {
                case .dashboard: DashboardView()
                case .fans: FansView()
                case .sensors: SensorsView()
                case .settings: SettingsView()
                }
            }
        }
        .background(WindowConfigurator())
    }
}

struct ConnectionBadge: View {
    @Environment(DaemonClient.self) private var client

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(client.isConnected ? Palette.series[2] : Palette.critical)
                .frame(width: 8, height: 8)
            Text(client.isConnected
                 ? L10n.t("Демон на связи", "Daemon connected")
                 : (client.lastError ?? L10n.t("Нет связи", "Disconnected")))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
