import CoreGraphics
import Foundation

/// The motion of a drop moving down a list, as plain numbers, so it can be tested
/// without drawing anything. `rows` are the rows' frames, top to bottom, never empty.
enum DropListMath {
    /// The row whose stretch holds `y`: each gap is split down its middle, so a tall
    /// row and a short one each own what is theirs, not whatever is nearer a centre.
    static func owner(of y: CGFloat, in rows: [CGRect]) -> Int {
        for index in 0..<(rows.count - 1) where y < (rows[index].maxY + rows[index + 1].minY) / 2 {
            return index
        }
        return rows.count - 1
    }

    /// Where a held drop sits for a pointer at `y`: on the row whose stretch holds the
    /// pointer, pulled a quarter of the way towards it.
    ///
    /// It always sits on a row. Following the pointer on a curve, it hung between two
    /// rows wherever a hand paused near the middle of a gap - a row-sized drop over the
    /// bottom of one and the top of the next, on neither. Now it leans towards the
    /// pointer, so it is plainly being held, and when the pointer crosses the middle of
    /// a gap it flows to the next row on its springs.
    static func stick(_ y: CGFloat, in rows: [CGRect]) -> CGFloat {
        let row = rows[owner(of: y, in: rows)]
        return row.midY + (y - row.midY) * 0.25
    }

    /// 0 over a row, rising to 1 four points out into a gap.
    static func gapness(at y: CGFloat, in rows: [CGRect]) -> CGFloat {
        let distance = rows.map { row in y < row.minY ? row.minY - y : y > row.maxY ? y - row.maxY : 0 }.min() ?? 0
        return min(distance / 4, 1)
    }

    /// The size a moving part of the drop reaches for: thinner and shorter the faster
    /// it goes, pinched further over a gap, and never thinner than a seventh.
    static func thinned(_ size: CGSize, speed: CGFloat, gapness: CGFloat) -> CGSize {
        let pace = min(abs(speed) / 750, 1)
        let width = size.width * max(0.14, (1 - 0.86 * pace) * (1 - 0.7 * gapness))
        return CGSize(width: width, height: size.height * (1 - 0.4 * pace))
    }

    /// Moving, the drop gives up the row's corners and rounds towards a pill; at rest
    /// it is the row's shape. The shader holds the radius to half the drop's size.
    static func cornerRadius(rest: CGFloat, speed: CGFloat) -> CGFloat {
        rest + min(abs(speed) / 250, 1) * 60
    }
}
