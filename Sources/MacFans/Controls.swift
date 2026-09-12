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
    var segmentWidth: CGFloat = 96
    var fontSize: CGFloat = 12.5

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                let isSelected = item.value == selection

                Text(item.title)
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.55))
                    .frame(width: segmentWidth)
                    .padding(.vertical, 6)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.white.opacity(0.16))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
                                )
                                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                                .matchedGeometryEffect(id: "selection", in: namespace)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                            selection = item.value
                        }
                    }
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
                )
        )
    }
}

/// A value readout that cannot change width as the number changes, so dragging a
/// slider never shifts the row around it.
struct FixedReadout: View {
    let text: String
    var width: CGFloat = 64
    var color: Color = .white

    var body: some View {
        Text(text)
            .font(.system(size: 12.5))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.88))
                Spacer(minLength: 12)
                FixedReadout(text: valueText)
            }
            Group {
                if let step {
                    Slider(value: $value, in: range, step: step) { editing in
                        if !editing { onCommit?() }
                    }
                } else {
                    Slider(value: $value, in: range) { editing in
                        if !editing { onCommit?() }
                    }
                }
            }
            .tint(tint)
            if let footnote {
                Text(footnote)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
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
            .foregroundStyle(.white.opacity(0.4))
    }
}

/// Content that fades and lifts into place, staggered by `delay`.
struct RiseIn: ViewModifier {
    let delay: Double
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .onAppear {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.85).delay(delay)) {
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
                .foregroundStyle(highlighted ? Palette.heat : .white.opacity(0.72))
            Text(Format.temperature(value))
                .font(.system(size: 10.5))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(highlighted ? Palette.heat.opacity(0.14) : .white.opacity(0.06))
                .overlay(Capsule().strokeBorder(
                    highlighted ? Palette.heat.opacity(0.3) : .white.opacity(0.12), lineWidth: 0.5))
        )
    }
}
