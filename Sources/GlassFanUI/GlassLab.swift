import SwiftUI

/// A bench for the drop's glass: a ground of contrasting lines and text, a drop that
/// follows the pointer, and every number of the rim on a slider. Opened with
/// `GLASSFAN_LAB=1`; it changes nothing outside its own process.
struct GlassLabView: View {
    @State private var tuning = LensTuning.shared
    @State private var at = Self.startingPoint ?? CGPoint(x: 300, y: 200)
    @State private var held = Self.startingPoint != nil
    @State private var pattern = Pattern(rawValue: ProcessInfo.processInfo.environment["GLASSFAN_LAB_PATTERN"] ?? "") ?? .track

    /// `GLASSFAN_LAB_DROP="x,y"`: the drop held there from the start, in the bench's
    /// own coordinates, for a screenshot without a pointer.
    private static var startingPoint: CGPoint? {
        let xy = (ProcessInfo.processInfo.environment["GLASSFAN_LAB_DROP"] ?? "").split(separator: ",").compactMap { Double($0) }
        return xy.count == 2 ? CGPoint(x: xy[0], y: xy[1]) : nil
    }

    enum Pattern: String, CaseIterable {
        case track, lines, text, apple, system
        var title: String {
            switch self {
            case .track:  return "Track"
            case .lines:  return "Lines"
            case .text:   return "Text"
            case .apple:  return "Apple"
            case .system: return "System"
            }
        }
    }

    @State private var systemChoice = 1
    @State private var systemOn = true
    @State private var systemValue = 0.5

    /// `GLASSFAN_LAB_GROUND=<png>`: a screenshot (2x) shown at its true size as the
    /// ground - Activity Monitor's own control, for a drop over the same pixels.
    private static let groundImage: NSImage? = {
        guard let path = ProcessInfo.processInfo.environment["GLASSFAN_LAB_GROUND"],
              let image = NSImage(contentsOfFile: path) else { return nil }
        if let rep = image.representations.first {
            image.size = NSSize(width: rep.pixelsWide / 2, height: rep.pixelsHigh / 2)
        }
        return image
    }()

    private var geometry: DropGeometry {
        var drop = DropGeometry.capsule(
            CGRect(x: at.x - tuning.dropWidth / 2, y: at.y - tuning.dropHeight / 2,
                   width: tuning.dropWidth, height: tuning.dropHeight),
            lift: 1, motion: 0)
        drop.maxMagnification = tuning.magnification
        return drop
    }

    var body: some View {
        HStack(spacing: 0) {
            bench
            Divider()
            knobs.frame(width: 340)
        }
        .frame(minWidth: 1100, minHeight: 640)
        // Always on the Mac's own screen: on a second display the shots come back at
        // 1x and every measurement in points is off by two.
        .onAppear {
            guard let screen = NSScreen.screens.max(by: { $0.backingScaleFactor < $1.backingScaleFactor }),
                  let window = NSApp.windows.first(where: { $0.title == "Glass lab" }) else { return }
            let size = window.frame.size
            window.setFrameOrigin(CGPoint(x: screen.frame.midX - size.width / 2,
                                          y: screen.frame.midY - size.height / 2))
        }
    }

    private var bench: some View {
        VStack(spacing: 10) {
            HStack {
                Picker("", selection: $pattern) {
                    ForEach(Pattern.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
                Spacer()
                Text(held ? "Drag to move · click to let go" : "Click to hold the drop")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.top, 10)

            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    ground(size: proxy.size)
                        .modifier(GlassDropRefraction(geometry: geometry, reach: CGSize(width: 48, height: 48)))
                    GlassDropLight(geometry: geometry, pointer: at, size: proxy.size)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            at = value.location
                            if value.translation == .zero { held.toggle() }
                        }
                )
            }
            .background(Color(red: 0.11, green: 0.11, blue: 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(12)
        }
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func ground(size: CGSize) -> some View {
        switch pattern {
        case .track:
            VStack(spacing: 40) {
                track(fontSize: 12.5, height: 34)
                track(fontSize: 15, height: 44)
                lines(size: CGSize(width: size.width - 80, height: 60), colours: [.white, .cyan, .yellow, .pink])
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .lines:
            VStack(spacing: 24) {
                lines(size: CGSize(width: size.width - 80, height: 90), colours: [.white, .cyan, .yellow, .pink])
                HStack(spacing: 24) {
                    columns(size: CGSize(width: 200, height: 120), colours: [.white, .green, .orange])
                    grid(size: CGSize(width: 200, height: 120))
                    columns(size: CGSize(width: 200, height: 120), colours: [.white, .white, .white])
                }
                lines(size: CGSize(width: size.width - 80, height: 60), colours: [.white, .white, .white, .white])
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .apple:
            if let image = Self.groundImage {
                Image(nsImage: image)
                    .interpolation(.none)
                    .frame(width: image.size.width, height: image.size.height)
                    .position(x: 20 + image.size.width / 2, y: 200 + image.size.height / 2)
            } else {
                Text("Set GLASSFAN_LAB_GROUND to a 2x screenshot").foregroundStyle(.secondary)
            }
        case .system:
            // The system's own glass over our ruled ground: whatever macOS does to
            // these lines is Apple's lens, measured rather than guessed.
            ZStack(alignment: .topLeading) {
                lines(size: CGSize(width: size.width - 40, height: size.height - 40),
                      colours: [.white, .cyan, .yellow, .pink])
                    .position(x: size.width / 2, y: size.height / 2)
                    .opacity(ProcessInfo.processInfo.environment["GLASSFAN_LAB_PLAIN"] == "1" ? 0 : 1)
                VStack(alignment: .leading, spacing: 30) {
                    Picker("", selection: $systemChoice) {
                        ForEach(0..<4) { i in Text(["Overview", "Fans", "Sensors", "Settings"][i]).tag(i) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 360)
                    Toggle("", isOn: $systemOn).toggleStyle(.switch).labelsHidden()
                    Slider(value: $systemValue).frame(width: 300)
                    Button("Button") {}.buttonStyle(.borderedProminent)
                }
                .padding(.leading, 60)
                .padding(.top, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .text:
            VStack(spacing: 28) {
                ForEach([11.0, 13.0, 17.0, 24.0], id: \.self) { size in
                    Text("Sensors S Fans 0123 Overview")
                        .font(.system(size: size, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The segmented control's ground as the app draws it, with labels, and a bright
    /// top edge.
    private func track(fontSize: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 2) {
            ForEach(["Overview", "Fans", "Sensors", "Settings"], id: \.self) { title in
                Text(title)
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(.white.opacity(title == "Fans" ? 1 : 0.55))
                    .padding(.horizontal, 16)
                    .frame(height: height - 6)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.06)],
                                         startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }

    private func lines(size: CGSize, colours: [Color]) -> some View {
        Canvas { context, _ in
            var y: CGFloat = 1
            var i = 0
            while y < size.height {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                             with: .color(colours[i % colours.count]))
                y += 6; i += 1
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func columns(size: CGSize, colours: [Color]) -> some View {
        Canvas { context, _ in
            var x: CGFloat = 1
            var i = 0
            while x < size.width {
                context.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)),
                             with: .color(colours[i % colours.count]))
                x += 6; i += 1
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func grid(size: CGSize) -> some View {
        Canvas { context, _ in
            var t: CGFloat = 0
            while t < max(size.width, size.height) {
                context.fill(Path(CGRect(x: t, y: 0, width: 1, height: size.height)), with: .color(.white.opacity(0.5)))
                context.fill(Path(CGRect(x: 0, y: t, width: size.width, height: 1)), with: .color(.white.opacity(0.5)))
                t += 10
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private var knobs: some View {
        @Bindable var tuning = tuning
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Rim").font(.headline)
                    Spacer()
                    Button("Reset") { tuning.reset() }
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(tuning.summary, forType: .string)
                    }
                }
                group("Drop") {
                    knob("Width", $tuning.dropWidth, 40...400)
                    knob("Height", $tuning.dropHeight, 20...200)
                    knob("Magnification", $tuning.magnification, 1...1.4, step: 0.01)
                    knob("Grow X (tabs)", $tuning.growX, 0...24)
                    knob("Grow Y (tabs)", $tuning.growY, 0...24)
                }
                group("Bead (the ashtray's wall)") {
                    knob("Outer image (pt)", $tuning.beadOut, 0...8, step: 0.1)
                    knob("Inner image (pt)", $tuning.beadIn, 0...8, step: 0.1)
                    knob("Mix inner/outer", $tuning.beadMix, 0...1, step: 0.05)
                    knob("Scatter", $tuning.beadBlur, 0...3, step: 0.05)
                    knob("Width (pt)", $tuning.rimWidth, 0.5...12, step: 0.1)
                    knob("Falloff", $tuning.rimSharp, 0.2...4, step: 0.1)
                }
                group("Colour and blur") {
                    knob("Dispersion", $tuning.dispersion, 0...1.5, step: 0.05)
                    knob("Along straight sides", $tuning.straightDispersion, 0...1, step: 0.05)
                    knob("Frost base", $tuning.frostBase, 0...2, step: 0.05)
                    knob("Frost gain", $tuning.frostGain, 0...3, step: 0.05)
                    knob("Gather light", $tuning.gather, 0...5, step: 0.1)
                }
                group("Edge line") {
                    knob("Width", $tuning.edgeWidth, 0.3...3, step: 0.1)
                    knob("Darkness", $tuning.edgeDark, 0...1, step: 0.05)
                    knob("Iridescence", $tuning.iridescence, 0...1, step: 0.05)
                }
            }
            .padding(14)
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func knob(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, step: Double = 1) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 11)).frame(width: 118, alignment: .leading)
            Slider(value: value, in: range, step: step)
            Text(String(format: step < 1 ? "%.2f" : "%.0f", value.wrappedValue))
                .font(.system(size: 11)).monospacedDigit().frame(width: 40, alignment: .trailing)
        }
    }
}
