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

    /// One point per sensor per sample, each line identified by the sensor's key.
    ///
    /// The line used to be identified by the sensor's display name. Several
    /// cores share the name "CPU core", so two of them charted together became
    /// one series, and Swift Charts drew a single line hopping between the two
    /// on every sample: a saw of seven to ten degrees that was really the gap
    /// between two cores, each of them steady.
    static func points(_ samples: [HistorySample], keys: [String],
                       gap: TimeInterval = .infinity) -> [SeriesPoint] {
        // Per sensor, not per sample: a sensor charted only from some point on has
        // a hole of its own even where the others are continuous.
        var lastTime: [String: Double] = [:]
        var segment: [String: Int] = [:]
        return samples.sorted { $0.t < $1.t }.flatMap { sample -> [SeriesPoint] in
            let date = Date(timeIntervalSince1970: sample.t)
            return keys.compactMap { key -> SeriesPoint? in
                guard let value = sample.temps[key] else { return nil }
                if let previous = lastTime[key], sample.t - previous > gap {
                    segment[key, default: 0] += 1
                }
                lastTime[key] = sample.t
                return SeriesPoint(date: date, value: value, series: key, segment: segment[key] ?? 0)
            }
        }
    }

    /// How long readings can stop before the line breaks: three buckets or three
    /// polls, whichever is longer, so a slow poll interval on a short window does
    /// not break the line at every other bucket.
    static func breakGap(window: TimeInterval, limit: Int, pollInterval: TimeInterval) -> TimeInterval {
        max(window / Double(max(limit, 1)), pollInterval) * 3
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

/// How many sensors the chart can draw, and what ticking one more does.
///
/// The limit is the palette's, not an arbitrary number: past it a series would have to
/// reuse a colour, and two lines the same colour is worse than a line not drawn. What
/// was worse still is what used to happen - the tick was accepted, the key appended,
/// and the chart went on drawing the first six. The box changed, nothing else did, and
/// the only hint was a count in the corner of the legend.
enum ChartSlots {
    static var limit: Int { Palette.series.count }

    /// The list after ticking or unticking `key`, or `nil` if there is no room.
    ///
    /// Removing always works. Adding is refused rather than accepted and ignored, so
    /// that the interface can say no where the pointer already is instead of saying
    /// nothing anywhere near it.
    static func toggling(_ key: String, in tracked: [String]) -> [String]? {
        if let index = tracked.firstIndex(of: key) {
            var updated = tracked
            updated.remove(at: index)
            return updated
        }
        guard tracked.count < limit else { return nil }
        return tracked + [key]
    }

    /// The ones actually drawn, of those ticked. Order decides: the chart takes the
    /// first it has colours for, so a key ticked when the chart was full waits its turn
    /// rather than pushing an older line off.
    static func drawn(_ tracked: [String]) -> ArraySlice<String> {
        tracked.prefix(limit)
    }
}
