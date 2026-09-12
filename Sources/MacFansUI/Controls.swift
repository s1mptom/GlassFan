import SwiftUI
import FanKit

/// Segmented control with a gliding glass selection.
///
/// Every segment has the SAME fixed width and the label weight never changes with
/// selection - both were causes of the control resizing under the pointer when you
/// clicked it.
struct GlassSegmented<Value: Hashable>: View {
    struct Item {
        let value: Value
        let title: String
    }

    let items: [Item]
    @Binding var selection: Value
    /// nil lets each segment size to its own label, as in the design.
    var segmentWidth: CGFloat? = 96
    var fontSize: CGFloat = 12.5
    /// Segments share the available width equally, so the control fills the row
    /// it sits in - the menu bar panel's mode switch spans the panel this way.
    var fills = false

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                let isSelected = item.value == selection

                Text(item.title)
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(isSelected ? Palette.ink : Palette.ink.opacity(0.55))
                    .frame(width: fills ? nil : segmentWidth)
                    .frame(maxWidth: fills ? .infinity : nil)
                    .padding(.horizontal, (segmentWidth == nil && !fills) ? 16 : 0)
                    .padding(.vertical, 6)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Palette.ink.opacity(0.16))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Palette.ink.opacity(0.18), lineWidth: 0.5)
                                )
                                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                                .matchedGeometryEffect(id: "selection", in: namespace)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selection = item.value }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(item.title)
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        // The glide belongs to the value, not to the tap that happened to cause
        // it. Wrapping the gesture in `withAnimation` animated only clicks, so
        // Command-1..4 and the menu bar's mode switch teleported the selection
        // instead of sliding it.
        .animation(.spring(response: 0.34, dampingFraction: 0.8), value: selection)
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Palette.ink.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Palette.ink.opacity(0.10), lineWidth: 0.5)
                )
        )
    }
}

/// A value readout that cannot change width as the number changes, so dragging a
/// slider never shifts the row around it.
struct FixedReadout: View {
    let text: String
    var width: CGFloat = 64
    var color: Color = Palette.ink

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .monospacedDigit()
            .foregroundStyle(color)
            .frame(width: width, alignment: .trailing)
    }
}

/// Label, fixed-width value, slider - the three-part row used all over Settings.
struct LabelledSlider: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    var footnote: String?
    var tint: Color = Palette.calm
    var onCommit: (() -> Void)?

    /// Snaps to `step` without handing it to the control, which would make it draw
    /// a tick for every stop.
    private var stepped: Binding<Double> {
        guard let step, step > 0 else { return $value }
        return Binding(
            get: { value },
            set: { value = (($0 - range.lowerBound) / step).rounded() * step + range.lowerBound }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.ink.opacity(0.6))
                Spacer(minLength: 12)
                FixedReadout(text: valueText, color: Palette.ink.opacity(0.9))
            }
            Slider(value: stepped, in: range) { editing in
                if !editing { onCommit?() }
            }
            .tint(tint)
            if let footnote {
                Text(footnote)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.ink.opacity(0.35))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Uppercase section caption used instead of boxed cards.
struct SectionCaption: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .medium))
            .tracking(0.7)
            .foregroundStyle(Palette.ink.opacity(0.4))
    }
}

enum Runtime {
    /// A preview canvas snapshots an early frame, so anything that animates itself in
    /// would be photographed mid-fade - or, with a delay on it, not yet started at all.
    /// Entrance animations skip straight to their end there.
    static let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
}

/// Content that fades and lifts into place, staggered by `delay`.
struct RiseIn: ViewModifier {
    let delay: Double
    @State private var shown = Runtime.isPreview

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .onAppear {
                guard !Runtime.isPreview else { return }
                // Brisk on purpose. This runs again every time a screen is
                // switched to, and a 0.7s spring delayed behind its neighbours
                // took most of a second to settle - charming once, tiresome by
                // the fourth tab press.
                withAnimation(.spring(response: 0.42, dampingFraction: 0.88).delay(delay)) {
                    shown = true
                }
            }
    }
}

extension View {
    func riseIn(_ delay: Double = 0) -> some View { modifier(RiseIn(delay: delay)) }
}

/// Wraps chips onto as many rows as they need.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// A sensor chip: name plus its current reading.
struct SensorChip: View {
    let name: String
    let value: Double?
    var highlighted: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.system(size: 10.5))
                .foregroundStyle(highlighted ? Palette.heat : Palette.ink.opacity(0.72))
            Text(Format.temperature(value))
                .font(.system(size: 10.5))
                .monospacedDigit()
                .foregroundStyle(Palette.ink.opacity(0.45))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(highlighted ? Palette.heat.opacity(0.14) : Palette.ink.opacity(0.06))
                .overlay(Capsule().strokeBorder(
                    highlighted ? Palette.heat.opacity(0.3) : Palette.ink.opacity(0.12), lineWidth: 0.5))
        )
    }
}

/// The one search field in the app. Both the sensor list and the curve-sensor picker
/// use it, so the two never drift into looking like different products.
struct GlassSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.ink.opacity(0.42))

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))

            // Clearing a long query by holding backspace is a chore; the affordance
            // only appears once there is something to clear.
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.ink.opacity(0.35))
                }
                .buttonStyle(.plain)
                .help(L10n.t("Очистить", "Clear"))
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: text.isEmpty)
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Palette.ink.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Palette.ink.opacity(0.11), lineWidth: 0.5))
        )
    }
}

/// A checkbox in the app's own ink. The system one draws a blue platform square that
/// sits on the glass like a sticker.
struct GlassCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(configuration.isOn ? Palette.calm : Palette.ink.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(configuration.isOn ? .clear : Palette.ink.opacity(0.18),
                                          lineWidth: 0.5)
                    )
                    .overlay {
                        if configuration.isOn {
                            // White on the blue fill in either scheme, so this one is
                            // deliberately not ink.
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 14, height: 14)

                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension ToggleStyle where Self == GlassCheckboxStyle {
    static var glassCheckbox: GlassCheckboxStyle { GlassCheckboxStyle() }
}
