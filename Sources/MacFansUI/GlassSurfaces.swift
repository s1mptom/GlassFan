import SwiftUI
import AppKit
import FanKit

/// The look of the glass, as two dials rather than a handful of presets: how much the
/// surfaces frost over, and whether they lean light or dark. Both are taste, and taste
/// depends on the wallpaper behind the window, so neither belongs in a constant.
enum GlassStyle {
    static let frostKey = "glassFrost"
    static let tintKey = "glassTint"

    /// 0 leaves the window a clear pane; 1 frosts it right over.
    static let defaultFrost = 0.62
    /// Negative darkens, positive lightens, 0 leaves the material as the system draws it.
    /// The design's glass is dark, so out of the box the tone leans that way.
    static let defaultTint = -0.35

    static let frostRange: ClosedRange<Double> = 0...1
    static let tintRange: ClosedRange<Double> = -1...1

    /// The veil laid over the blur: tone picks its lightness, frost its density.
    static func scrim(frost: Double, tint: Double) -> Color {
        Color(white: scrimLevel(tint)).opacity(scrimAlpha(frost))
    }

    /// Asymmetric on purpose. Darkening only has to reach black, which is a short
    /// trip from the material's own lightness; lightening has to travel all the way
    /// to white, and a gentler slope stranded the whole upper half of the dial in
    /// mid-grey - the one backing no ink reads well on.
    private static func scrimLevel(_ tint: Double) -> Double {
        let level = tint >= 0 ? 0.12 + tint * 0.84 : 0.12 + tint * 0.45
        return min(max(level, 0), 1)
    }

    private static func scrimAlpha(_ frost: Double) -> Double {
        min(max(frost, 0), 1) * 0.88
    }

    /// Whether the backing has been dialled light enough that white text would sink
    /// into it. Both dials matter: a light veil that is barely there still leaves a
    /// dark window, so lightness is weighed by how much of it is actually laid down.
    ///
    /// The material underneath is the dark one, hence the 0.1 floor the veil is mixed
    /// over. A clear pane therefore counts as dark, which is the right call: with no
    /// veil the desktop shows through and light ink would depend on the wallpaper.
    static func isLight(frost: Double, tint: Double) -> Bool {
        let alpha = scrimAlpha(frost)
        return scrimLevel(tint) * alpha + 0.1 * (1 - alpha) > 0.5
    }
}

/// Real behind-window blur. A SwiftUI Material only blurs content inside its own
/// window, so in a transparent window it is just a translucent fill and the desktop
/// behind stays sharp - which is exactly how the frosting went missing.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// Window backing: blur underneath, a veil on top whose density and lightness are the
/// user's two dials.
struct GlassBackground: View {
    @AppStorage(GlassStyle.frostKey) private var frost = GlassStyle.defaultFrost
    @AppStorage(GlassStyle.tintKey) private var tint = GlassStyle.defaultTint

    var body: some View {
        ZStack {
            VisualEffectBackground()
            Rectangle().fill(GlassStyle.scrim(frost: frost, tint: tint))
        }
        .ignoresSafeArea()
    }
}

enum Diagnostics {
    /// Straight to stderr: a redirected GUI process buffers stdout, and a diagnostic
    /// that only appears at exit is no diagnostic at all.
    static func log(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}

/// Makes the host window itself transparent, and strips the opaque fill AppKit puts
/// behind a split view, so what is behind the window shows through.
///
/// Reports what it actually managed to change, because "the window looks opaque" and
/// "the code that makes it transparent never ran" are indistinguishable from outside.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        guard !Runtime.isPreview else { return view }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard let window = view.window else {
                Diagnostics.log("[window] no host window found")
                return
            }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            Self.centerOnce(window)

            let cleared = Self.clearOpaqueBackings(in: window.contentView)
            Diagnostics.log("[window] isOpaque=\(window.isOpaque) "
                + "background=\(window.backgroundColor.alphaComponent) "
                + "clearedBackings=\(cleared)")
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}

    private nonisolated(unsafe) static var hasCentred = false

    private static func centerOnce(_ window: NSWindow) {
        guard !hasCentred else { return }
        hasCentred = true
        window.center()
    }

    /// AppKit fills the split view with an opaque colour that sits above anything
    /// SwiftUI puts behind it. That fill has to go, or the frosting is covered from
    /// above.
    ///
    /// Deliberately NOT touching NSVisualEffectViews here: SwiftUI builds its own for
    /// the sidebar material and for every glass surface, and forcing those to
    /// behind-window blending punches the window through to the desktop and the whole
    /// interface disappears. That was tried; it did exactly that.
    @discardableResult
    private static func clearOpaqueBackings(in view: NSView?) -> Int {
        guard let view else { return 0 }
        var cleared = 0
        if let split = view as? NSSplitView {
            split.wantsLayer = true
            split.layer?.backgroundColor = NSColor.clear.cgColor
            cleared += 1
        }
        for subview in view.subviews {
            cleared += clearOpaqueBackings(in: subview)
        }
        return cleared
    }
}
