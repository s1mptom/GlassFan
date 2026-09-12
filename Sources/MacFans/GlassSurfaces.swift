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
    static let defaultTint = 0.0

    static let frostRange: ClosedRange<Double> = 0...1
    static let tintRange: ClosedRange<Double> = -1...1

    /// Asymmetric on purpose: a wash of white reads much stronger than the same amount
    /// of black, so lightening is given a shorter lever.
    static func tint(_ amount: Double) -> Color {
        amount >= 0 ? .white.opacity(amount * 0.22) : .black.opacity(-amount * 0.40)
    }
}

/// Window backing. Drawn as a real view rather than a material shape style, because a
/// shape style cannot be dimmed or tinted by degrees.
struct GlassBackground: View {
    @AppStorage(GlassStyle.frostKey) private var frost = GlassStyle.defaultFrost
    @AppStorage(GlassStyle.tintKey) private var tint = GlassStyle.defaultTint

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .opacity(frost)
            Rectangle()
                .fill(GlassStyle.tint(tint))
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
