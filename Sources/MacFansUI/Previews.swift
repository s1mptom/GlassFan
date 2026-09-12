#if DEBUG
import SwiftUI
import FanKit

/// Every screen as the whole window, at the size the design's window was drawn at, fed from
/// the fixture.
///
/// The window backing blurs whatever is behind the window, and a preview canvas has
/// nothing behind it, so the glass reads flatter here than in the running app.
/// Layout, type, colour and state are true; the frosting is not.
private struct PreviewShell: View {
    private let client: DaemonClient

    init(_ screen: Screen = .overview,
         connected: Bool = true,
         frost: Double = GlassStyle.defaultFrost,
         tint: Double = GlassStyle.defaultTint) {
        // The window restores these, so seeding them is how a preview picks a screen
        // and a glass setting - and it exercises the same path the app really takes.
        UserDefaults.standard.set(screen.rawValue, forKey: Screen.storageKey)
        UserDefaults.standard.set(frost, forKey: GlassStyle.frostKey)
        UserDefaults.standard.set(tint, forKey: GlassStyle.tintKey)
        client = .demo(connected: connected)
    }

    var body: some View {
        MainWindow()
            .environment(client)
            .environment(DaemonInstaller())
            .frame(width: 1008, height: 640)
    }
}

#Preview("Overview") { PreviewShell(.overview) }

#Preview("Fans") { PreviewShell(.fans) }

#Preview("Sensors") { PreviewShell(.sensors) }

#Preview("Settings") { PreviewShell(.settings) }

/// The case the Tone dial used to break: a backing light enough that white text
/// would sink into it. The ink should have flipped to dark.
#Preview("Light glass") { PreviewShell(.overview, frost: 1, tint: 1) }

/// A clear pane, the other end of the same dial.
#Preview("Clear glass") { PreviewShell(.overview, frost: 0.08, tint: 0) }

#Preview("Daemon missing") { PreviewShell(.overview, connected: false) }

/// The popover behind the plus in Curve sensors, which has no other way to be seen
/// short of clicking into it.
#Preview("Sensor picker") {
    @Previewable @State var selection = ["TCMz", "TaRT"]
    return SensorPicker(selection: $selection)
        .environment(DaemonClient.demo())
        .frame(width: 360, height: 420)
}

#Preview("Menu bar") {
    MenuBarPanel()
        .environment(DaemonClient.demo())
        .environment(DaemonInstaller())
}
#endif
