import SwiftUI
import AppKit
import FanKit

/// How much of the desktop shows through the window. A matter of taste and of what
/// sits behind the window, so it is the user's dial, not a constant of mine.
enum WindowTranslucency: String, CaseIterable, Identifiable {
    case dense, medium, clear, glassOnly

    static let storageKey = "windowTranslucency"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dense:     return L10n.t("Плотное", "Dense")
        case .medium:    return L10n.t("Среднее", "Medium")
        case .clear:     return L10n.t("Прозрачное", "Clear")
        case .glassOnly: return L10n.t("Только стекло", "Glass only")
        }
    }

    var material: AnyShapeStyle {
        switch self {
        case .dense:  return AnyShapeStyle(.regularMaterial)
        case .medium: return AnyShapeStyle(.thinMaterial)
        case .clear:  return AnyShapeStyle(.ultraThinMaterial)
        // No window background at all: the desktop is right there and only the cards
        // are glass. As transparent as the window gets while staying usable.
        case .glassOnly: return AnyShapeStyle(.clear)
        }
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
