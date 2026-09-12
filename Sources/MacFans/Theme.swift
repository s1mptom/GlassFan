import SwiftUI
import AppKit

extension NSColor {
    convenience init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
        self.init(srgbRed: CGFloat((value >> 16) & 0xff) / 255,
                  green: CGFloat((value >> 8) & 0xff) / 255,
                  blue: CGFloat(value & 0xff) / 255,
                  alpha: 1)
    }
}

extension Color {
    /// Resolves per appearance, so a palette step chosen for the dark surface is
    /// actually used in dark mode rather than a washed-out flip of the light one.
    static func adaptive(light: String, dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }
}

/// Chart colors. Fixed order, never cycled, validated for colour-vision deficiency
/// and contrast against both surfaces before use.
enum Palette {
    static let series: [Color] = [
        .adaptive(light: "#2a78d6", dark: "#3987e5"), // blue
        .adaptive(light: "#eb6834", dark: "#d95926"), // orange
        .adaptive(light: "#1baf7a", dark: "#199e70"), // aqua
        .adaptive(light: "#eda100", dark: "#c98500"), // yellow
        .adaptive(light: "#e87ba4", dark: "#d55181"), // magenta
        .adaptive(light: "#008300", dark: "#008300"), // green
    ]

    /// Slot for a series by its position. Past the palette it folds into grey rather
    /// than inventing a hue.
    static func color(_ index: Int) -> Color {
        index < series.count ? series[index] : .secondary
    }

    static let warning = Color.adaptive(light: "#eda100", dark: "#c98500")
    static let critical = Color.adaptive(light: "#e34948", dark: "#e66767")
    static let calm = Color.adaptive(light: "#2a78d6", dark: "#3987e5")
}

extension View {
    /// One glass card, used everywhere so the surfaces stay consistent.
    func glassCard(cornerRadius: CGFloat = 20) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, padding: 16))
    }

    /// A glass surface without the card padding, for tiles and chips.
    func glassSurface(cornerRadius: CGFloat, padding: CGFloat = 0) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, padding: padding))
    }
}

/// Cards stay as clear as glass gets. Frost and tone belong to the window backing
/// alone: dimming the cards as well only made the readable part of the interface
/// murky without making the window any more see-through.
struct GlassCard: ViewModifier {
    let cornerRadius: CGFloat
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}

enum Format {
    static func temperature(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f°", value)
    }

    static func temperatureFine(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f °C", value)
    }

    /// Zero is a real reading on Apple Silicon - the fans stop completely when cool -
    /// so it is shown as zero, and only a missing value becomes a dash.
    static func rpm(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f", value)
    }
}
