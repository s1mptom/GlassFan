import Foundation
import FanKit

/// Thinning the history for the chart, done so that a point already drawn can
/// never move.
///
/// The old thinning kept every Nth sample counted from the start of the array.
/// Every tick appends one reading and lets one fall off the left edge, so the
/// array shifts by one and "every fifth" lands on a different set of timestamps
/// than it did a second ago. The whole curve breathed - through the fast
/// wobble in the data - and because its extremes moved with it, so did the
/// scale. That is the jumping that was reported: not the new point, the old
/// ones.
///
/// Samples are grouped into buckets keyed by absolute time instead. A bucket
/// that is complete has the same members whenever it is looked at, so its mean
/// is a fixed point until it scrolls off the left. Only the newest bucket is
/// still filling, and that one is allowed to move: it is the live end.
enum ChartSampling {

    /// One mean sample per bucket of `window / limit` seconds, oldest first.
    ///
    /// Up to `limit + 1` of them: a full window of complete buckets, plus the
    /// live one that has just begun on top when `now` sits on a boundary.
    ///
    /// Only whole buckets inside the window are kept. The bucket the left edge
    /// cuts through is dropped rather than shown: its mean would drift as its
    /// members leave, which is exactly the motion this exists to remove.
    static func bucketed(_ samples: [HistorySample],
                         window: TimeInterval,
                         now: TimeInterval,
                         limit: Int) -> [HistorySample] {
        guard limit > 0, window > 0 else { return [] }
        let bucket = window / Double(limit)
        let firstKey = Int(((now - window) / bucket).rounded(.up))

        struct Sum {
            var count = 0
            var temps: [String: Double] = [:]
            var rpm: [Double] = []
        }
        var sums: [Int: Sum] = [:]

        for sample in samples {
            let key = Int((sample.t / bucket).rounded(.down))
            guard key >= firstKey else { continue }
            var sum = sums[key] ?? Sum()
            sum.count += 1
            for (sensor, value) in sample.temps {
                sum.temps[sensor, default: 0] += value
            }
            if sum.rpm.isEmpty {
                sum.rpm = sample.fanRPM
            } else {
                for index in 0..<min(sum.rpm.count, sample.fanRPM.count) {
                    sum.rpm[index] += sample.fanRPM[index]
                }
            }
            sums[key] = sum
        }

        return sums.keys.sorted().map { key in
            let sum = sums[key]!
            let n = Double(sum.count)
            // Stamped at the bucket's start, which depends on the key alone and
            // not on which readings happened to fall in it.
            return HistorySample(
                t: Double(key) * bucket,
                temps: sum.temps.mapValues { $0 / n },
                fanRPM: sum.rpm.map { $0 / n })
        }
    }

    /// A range that holds the data with a little air, snapped outward to whole
    /// `step`s so that a reading drifting by a tenth of a degree does not redraw
    /// the axis. Never anchored at zero: room temperature is not a meaningful
    /// floor for a temperature chart.
    static func domain(for values: [Double], step: Double = 5) -> ClosedRange<Double>? {
        guard step > 0, let low = values.min(), let high = values.max() else { return nil }
        let lower = ((low - 1) / step).rounded(.down) * step
        let upper = ((high + 1) / step).rounded(.up) * step
        return lower...max(upper, lower + step)
    }
}
