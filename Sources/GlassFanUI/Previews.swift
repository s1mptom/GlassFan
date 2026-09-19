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
         alarming: Bool = false,
         fanless: Bool = false,
         sleptAt: Int? = nil,
         frost: Double = GlassStyle.defaultFrost,
         tint: Double = GlassStyle.defaultTint,
         sensorFilter: SensorFilter = .essential,
         sensorSort: SensorSort = .importance,
         curves: Int = 1) {
        // The window restores these, so seeding them is how a preview picks a screen
        // and a glass setting - and it exercises the same path the app really takes.
        UserDefaults.standard.set(screen.rawValue, forKey: Screen.storageKey)
        UserDefaults.standard.set(frost, forKey: GlassStyle.frostKey)
        UserDefaults.standard.set(tint, forKey: GlassStyle.tintKey)
        UserDefaults.standard.set(sensorFilter.rawValue, forKey: SensorsView.filterKey)
        UserDefaults.standard.set(sensorSort.rawValue, forKey: SensorsView.sortKey)
        UserDefaults.standard.set(sensorSort.ascendingByDefault, forKey: SensorsView.ascendingKey)
        client = .demo(connected: connected, alarming: alarming, fanless: fanless, sleptAt: sleptAt, curves: curves)
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

/// Three curves on fan 1: palm rests, CPU, GPU - the CPU's setting the speed.
#Preview("Fans · three curves") { PreviewShell(.fans, curves: 3) }

#Preview("Sensors") { PreviewShell(.sensors) }

/// Everything the SMC reports, hottest first within each group.
#Preview("Sensors · all by temperature") { PreviewShell(.sensors, sensorFilter: .all, sensorSort: .temperature) }

#Preview("Settings") { PreviewShell(.settings) }

/// The case the Tone dial used to break: a backing light enough that white text
/// would sink into it. The ink should have flipped to dark.
#Preview("Light glass") { PreviewShell(.overview, frost: 1, tint: 1) }

/// A clear pane, the other end of the same dial.
#Preview("Clear glass") { PreviewShell(.overview, frost: 0.08, tint: 0) }

#Preview("Daemon missing") { PreviewShell(.overview, connected: false) }

/// One fan run away on the emergency rule, the other refusing writes - the states
/// that must not look like an ordinary afternoon.
#Preview("Trouble") { PreviewShell(.overview, alarming: true) }

/// Three minutes of sleep in the middle of the window: the lines break across it.
#Preview("After a sleep") { PreviewShell(.overview, sleptAt: 420) }

/// Every MacBook Air: sensors, and no fans at all.
#Preview("No fans · overview") { PreviewShell(.overview, fanless: true) }
#Preview("No fans · fans") { PreviewShell(.fans, fanless: true) }

/// The popover behind the plus in Curve sensors, which has no other way to be seen
/// short of clicking into it.
#Preview("Sensor picker") {
    @Previewable @State var selection = ["TCMz", "Th02"]
    return SensorPicker(selection: $selection)
        .environment(DaemonClient.demo())
        .frame(width: 360, height: 420)
}

/// The blades at a ladder of speeds, to judge how far the motion wash has to
/// smear before the gaps between them close.
#Preview("Blades at speed") {
    let limits = FanLimits(minRPM: 1499, maxRPM: 5348)
    HStack(spacing: 18) {
        ForEach([0.0, 900, 1800, 2600, 3800, 5348], id: \.self) { rpm in
            VStack(spacing: 8) {
                FanDial(rpm: rpm, limits: limits, controlled: rpm > 0, size: 116)
                Text(Format.rpm(rpm))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink.opacity(0.4))
            }
        }
    }
    .padding(22)
    .background(Color(white: 0.06))
    .preferredColorScheme(.dark)
}

/// The two glass dials, crossed: Frost down the page, Tone across it, over a
/// stand-in for the desktop so the frosting has something to hide. The real
/// window cannot show this in a preview - there is nothing behind it to blur.
///
/// What to check. Every row must change left to right, including the top one:
/// that is the Tone dial working at a Frost of zero, which it did not. And the
/// middle column must be the same lightness all the way down: that is the
/// frosting hiding more of the desktop without shifting the tone.
#Preview("Glass dials") {
    let frosts: [Double] = [0, 0.35, 0.7, 1]
    let tones: [Double] = [-1, -0.5, 0, 0.5, 1]

    return VStack(spacing: 5) {
        ForEach(frosts, id: \.self) { frost in
            HStack(spacing: 5) {
                ForEach(tones, id: \.self) { tone in
                    ZStack {
                        LinearGradient(colors: [.purple, .blue, .teal],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        Rectangle().fill(GlassStyle.frostVeil(frost))
                        Rectangle().fill(GlassStyle.toneVeil(tone))
                        VStack(spacing: 1) {
                            Text("2600")
                                .font(.system(size: 17, weight: .semibold))
                                .monospacedDigit()
                            Text("frost \(Int(frost * 100)) · tone \(Int(tone * 100))")
                                .font(.system(size: 8))
                                .foregroundStyle(Palette.ink.opacity(0.55))
                        }
                        .foregroundStyle(Palette.ink)
                    }
                    .environment(\.colorScheme, GlassStyle.isLight(tint: tone) ? .light : .dark)
                    .frame(width: 132, height: 66)
                }
            }
        }
    }
    .padding(12)
    .background(Color(white: 0.08))
}

/// The disc travels to the screen as a bitmap on a Core Animation layer; the
/// shape beside it is drawn by SwiftUI directly. The blades are chiral - swept
/// back against the spin - so a layer that flipped its contents would show
/// here as the two curling opposite ways.
#Preview("Blade orientation") {
    HStack(spacing: 30) {
        FanDial(rpm: 0, limits: FanLimits(minRPM: 1499, maxRPM: 5348), controlled: false,
                size: 300, showsCaption: false, showsValue: false)
        FanBlades().fill(Color.white.opacity(0.5)).frame(width: 300, height: 300)
    }
    .padding(20)
    .background(Color(white: 0.06))
    .preferredColorScheme(.dark)
}

/// What stands in for a screen while there is no daemon, in each of its states.
#Preview("No daemon") {
    let states: [DaemonAbsence] = [.working(.update), .connecting, .silent, .notInstalled]
    Grid(horizontalSpacing: 1, verticalSpacing: 1) {
        GridRow { cell(states[0]); cell(states[1]) }
        GridRow { cell(states[2]); cell(states[3]) }
    }
    .background(Palette.ink.opacity(0.1))
    .preferredColorScheme(.dark)
}

private func cell(_ absence: DaemonAbsence) -> some View {
    DaemonAbsenceView(absence: absence) {}
        .frame(width: 520, height: 300)
        .background(Color(white: 0.16))
}

#Preview("Menu bar") {
    MenuBarPanel()
        .environment(DaemonClient.demo())
        .environment(DaemonInstaller())
}
#endif
