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

    /// Where a held drop sits for a pointer at `y`.
    ///
    /// It sticks to the row it is over: inside the row's stretch it lags the pointer
    /// on a steep curve, so it barely leaves the row's middle until the pointer is
    /// most of the way out - then it gives and runs to the edge, where the next row's
    /// own curve takes it from the other side. The two curves meet at the boundary,
    /// so the drop never jumps.
    static func stick(_ y: CGFloat, in rows: [CGRect]) -> CGFloat {
        let index = owner(of: y, in: rows)
        let row = rows[index]
        let above = index > 0 ? (rows[index - 1].maxY + row.minY) / 2 : row.minY
        let below = index < rows.count - 1 ? (row.maxY + rows[index + 1].minY) / 2 : row.maxY
        let offset = y - row.midY
        let reach = offset >= 0 ? below - row.midY : row.midY - above
        guard reach > 0 else { return row.midY }
        let t = min(abs(offset) / reach, 1)
        return row.midY + (offset < 0 ? -1 : 1) * reach * t * t * t
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
