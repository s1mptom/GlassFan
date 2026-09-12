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

    /// Two veils, not one.
    ///
    /// A single veil had to carry both dials: its opacity was the frosting and its
    /// lightness was the tone. That couples them, and both symptoms were reported.
    /// At a Frost of zero there is no veil, so nothing for a tone to colour and the
    /// Tone dial does nothing whatever; and once Tone is off centre, moving Frost
    /// changes the lightness too, because it changes how much of a tinted veil is
    /// laid down. Measured over the old code, the whole Tone range at Frost 0.2
    /// moved the backing from 0.08 to 0.25, against 0.01 to 0.86 at Frost 1.
    ///
    /// Separated, each dial does exactly the one thing its label claims.

    /// The frosting: a veil the same lightness as the material beneath it, so
    /// laying more of it down hides more of the desktop without shifting the tone.
    /// Adaptive, because the material follows the appearance and a fixed dark veil
    /// would darken a light one.
    static func frostVeil(_ frost: Double) -> Color {
        materialMatch.opacity(frostOpacity(frost))
    }

    /// The tone: black or white over the top. It applies whatever the frosting is,
    /// which is the whole point of separating the two.
    static func toneVeil(_ tint: Double) -> Color {
        Color(white: toneIsWhite(tint) ? 1 : 0).opacity(toneOpacity(tint))
    }

    // The arithmetic behind the veils, kept as plain numbers so it can be tested
    // without resolving a Color. Resolving an adaptive colour reaches into AppKit,
    // and doing that from a test running off the main actor deadlocked the runner.

    /// How much of the frost veil is laid down. Never fully opaque: some of the
    /// desktop always shows, or it is not glass.
    static func frostOpacity(_ frost: Double) -> Double {
        min(max(frost, 0), 1) * 0.92
    }

    static func toneOpacity(_ tint: Double) -> Double {
        abs(min(max(tint, -1), 1)) * toneAuthority
    }

    static func toneIsWhite(_ tint: Double) -> Bool {
        tint >= 0
    }

    /// How much of the window the tone veil may claim at the ends of its travel.
    /// High enough that the light end is genuinely light rather than the mid-grey
    /// no ink reads well on.
    static let toneAuthority = 0.85

    /// Apparent lightness of the material itself, and a veil matching it. The
    /// level is what makes the frost veil lightness-neutral, so it is not private:
    /// a test checks that the veil's colour really does sit at it.
    static let materialLevel = 0.1
    private static let materialMatch = Color.adaptive(light: "#e6e8ec", dark: "#191c21")

    /// What the backing ends up looking like, 0 black to 1 white.
    ///
    /// Only the tone moves it: the frost veil matches the material, so it is
    /// lightness-neutral by construction and does not appear here at all. That is
    /// the property the two tests assert.
    static func apparentLightness(tint: Double) -> Double {
        let tint = min(max(tint, -1), 1)
        let alpha = abs(tint) * toneAuthority
        return (tint >= 0 ? 1 : 0) * alpha + materialLevel * (1 - alpha)
    }

    /// Whether the backing has been dialled light enough that white text would sink
    /// into it, in which case `Palette.ink` flips to dark. A function of the tone
    /// alone now, so the ink flips at the same place on the dial whatever the
    /// frosting - it used to depend on both and move about.
    static func isLight(tint: Double) -> Bool {
        apparentLightness(tint: tint) > 0.5
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
            Rectangle().fill(GlassStyle.frostVeil(frost))
            Rectangle().fill(GlassStyle.toneVeil(tint))
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
