import SwiftUI

/// What a curve is doing, which is what colours it: the one being edited is blue, the
/// one setting the fan's speed orange, the rest grey.
enum CurveRole: Equatable {
    case editing, driving, idle

    /// The edited curve is blue even when it is also the one driving: it is the one
    /// the hand is on, and the live marker already says what drives.
    static func of(_ index: Int, editing: Int, driving: Int?) -> CurveRole {
        index == editing ? .editing : index == driving ? .driving : .idle
    }

    var colour: Color {
        switch self {
        case .editing: Palette.calm
        case .driving: Palette.heat
        case .idle: Palette.ink.opacity(0.28)
        }
    }
}

/// A curve's number in a dot: on its group's card, and at the end of its line.
struct CurveNumber: View {
    let number: Int
    let role: CurveRole
    var size: CGFloat = 16

    var body: some View {
        Text("\(number)")
            .font(.system(size: size * 0.62, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(ink)
            .frame(width: size, height: size)
            .background(Circle().fill(fill))
            .overlay(Circle().strokeBorder(stroke, lineWidth: 0.5))
    }

    private var ink: Color {
        switch role {
        case .editing: .white
        case .driving: Palette.heat
        case .idle: Palette.ink.opacity(0.55)
        }
    }

    private var fill: Color {
        switch role {
        case .editing: Palette.calm
        case .driving: Palette.heat.opacity(0.16)
        case .idle: Palette.ink.opacity(0.06)
        }
    }

    private var stroke: Color {
        switch role {
        case .editing: Palette.calm
        case .driving: Palette.heat.opacity(0.45)
        case .idle: Palette.ink.opacity(0.16)
        }
    }
}

/// Where the numbers go at the right-hand ends of the curves.
///
/// Two curves that end at the same speed would put their numbers on top of each
/// other. They are kept `spacing` apart: the edited curve's number keeps its true
/// place, the others step aside - down the margin, or up it when there is no room
/// below - and are drawn with a leader back to where their line really ends.
enum CurveNumberLayout {
    struct Placed: Equatable {
        var index: Int
        /// Where the curve's line ends.
        var lineY: CGFloat
        /// Where its number sits.
        var y: CGFloat
    }

    static func place(ends: [CGFloat], editing: Int, spacing: CGFloat = 20,
                      within range: ClosedRange<CGFloat>) -> [Placed] {
        let order = ends.indices.sorted { a, b in
            if (a == editing) != (b == editing) { return a == editing }
            return ends[a] < ends[b]
        }
        var placed: [Placed] = []
        for index in order {
            let lineY = min(max(ends[index], range.lowerBound), range.upperBound)
            let clashes = { (y: CGFloat) in placed.contains { abs($0.y - y) < spacing - 0.001 } }
            var y = lineY
            while clashes(y) { y += spacing }
            if y > range.upperBound {
                y = lineY
                while clashes(y) { y -= spacing }
            }
            placed.append(Placed(index: index, lineY: lineY, y: y))
        }
        return placed.sorted { $0.index < $1.index }
    }
}
