import Testing
import Foundation
import FanKit
@testable import GlassFanUI

/// The chart was reported as jumping every tick - the already-drawn part of
/// the line, and the scale after it. The thinning picked every Nth sample by
/// array index, and the array shifts by one each tick, so each tick drew a
/// different subset of the same history. These pin the property that fixes it:
/// a point, once drawn, stays where it is until it scrolls off.
@Suite("Chart sampling")
struct ChartSamplingTests {
    /// One reading a second with the kind of fast wobble the old thinning
    /// aliased against.
    private func history(through end: Int) -> [HistorySample] {
        (0...end).map { second in
            let t = Double(second)
            return HistorySample(t: t,
                                 temps: ["A": 70 + 3 * sin(t / 11), "B": 35 + sin(t / 7)],
                                 fanRPM: [2600 + 100 * sin(t / 9)])
        }
    }

    @Test("a point already drawn does not move on the next tick")
    func drawnPointsAreStable() {
        let before = ChartSampling.bucketed(history(through: 1000), window: 900, now: 1000, limit: 180)
        let after = ChartSampling.bucketed(history(through: 1001), window: 900, now: 1001, limit: 180)

        let earlier = Dictionary(uniqueKeysWithValues: before.map { ($0.t, $0) })
        // Everything but the newest bucket, which is still filling and may move.
        for sample in after.dropLast() {
            guard let previous = earlier[sample.t] else { continue }
            #expect(previous == sample, "bucket at \(sample.t) changed between ticks")
        }
        // And it is a real comparison, not a vacuous one.
        #expect(after.dropLast().filter { earlier[$0.t] != nil }.count > 100)
    }

    @Test("a partial bucket at the left edge is dropped rather than shown drifting")
    func leftEdgeBucketIsWhole() {
        let bucketed = ChartSampling.bucketed(history(through: 1000), window: 900, now: 1000, limit: 180)
        let bucket = 900.0 / 180
        #expect(bucketed.first!.t >= 1000 - 900)
        #expect(bucketed.first!.t.truncatingRemainder(dividingBy: bucket) == 0)
    }

    @Test("buckets are stamped from the key, ordered, never in the future")
    func bucketTimestamps() {
        let bucketed = ChartSampling.bucketed(history(through: 1000), window: 900, now: 1000, limit: 180)
        for (a, b) in zip(bucketed, bucketed.dropFirst()) {
            #expect(b.t > a.t)
        }
        #expect(bucketed.last!.t <= 1000)
        // A full window of complete buckets plus the live one.
        #expect(bucketed.count <= 181)
    }

    @Test("a bucket is the mean of its members")
    func bucketIsMean() {
        let flat = (0...9).map { HistorySample(t: Double($0), temps: ["A": Double($0)], fanRPM: [Double($0) * 10]) }
        let one = ChartSampling.bucketed(flat, window: 10, now: 10, limit: 1)
        #expect(one.count == 1)
        #expect(one[0].temps["A"] == 4.5)
        #expect(one[0].fanRPM == [45])
    }

    @Test("the scale snaps to whole steps and ignores tenth-of-a-degree drift")
    func domainIsSnapped() {
        let a = ChartSampling.domain(for: [40.1, 60.2])
        let b = ChartSampling.domain(for: [40.3, 60.4])
        #expect(a == b)
        #expect(a == 35...65)
        #expect(ChartSampling.domain(for: []) == nil)
    }

    @Test("a flat line still gets a range to sit in")
    func flatDomainHasHeight() {
        let d = ChartSampling.domain(for: [50, 50])!
        #expect(d.upperBound > d.lowerBound)
        #expect(d.contains(50))
    }
}

/// The CPU line drew a saw of seven to ten degrees while the cores it showed
/// moved by one: two cores share the display name "CPU core", the chart used the
/// name as the line's identity, and so it drew one line hopping between them.
@Suite("Chart series")
struct ChartSeriesTests {
    @Test("two sensors with the same name stay two lines")
    func sameNameTwoSeries() {
        let history = (0..<10).map {
            HistorySample(t: Double($0), temps: ["Tp0D": 72, "Tp0E": 58], fanRPM: [])
        }
        let points = ChartSampling.points(history, keys: ["Tp0D", "Tp0E"])
        let byLine = Dictionary(grouping: points, by: \.series)

        #expect(byLine.count == 2)
        // Each line is flat - no hopping between the two cores.
        #expect(Set(byLine["Tp0D"]!.map(\.value)) == [72])
        #expect(Set(byLine["Tp0E"]!.map(\.value)) == [58])
        // And every point is its own mark.
        #expect(Set(points.map(\.id)).count == points.count)
    }
}

/// After a sleep the line drew a straight edge across the time nothing was
/// measured. It breaks there now.
@Suite("Chart breaks")
struct ChartBreakTests {
    @Test("readings that stop and resume make two runs of one sensor")
    func sleepBreaksTheLine() {
        let before = (0..<5).map { HistorySample(t: Double($0), temps: ["A": 60], fanRPM: []) }
        let after = (0..<5).map { HistorySample(t: 600 + Double($0), temps: ["A": 50], fanRPM: []) }
        let points = ChartSampling.points(before + after, keys: ["A"], gap: 15)
        #expect(Set(points.map(\.segment)) == [0, 1])
        #expect(Set(points.map(\.series)) == ["A"])
        #expect(points.filter { $0.segment == 0 }.allSatisfy { $0.value == 60 })
    }

    @Test("steady readings stay one run")
    func noBreak() {
        let samples = (0..<100).map { HistorySample(t: Double($0), temps: ["A": 60, "B": 40], fanRPM: []) }
        let points = ChartSampling.points(samples, keys: ["A", "B"], gap: 15)
        #expect(Set(points.map(\.segment)) == [0])
    }

    @Test("the break gap follows a slow poll, not just the bucket")
    func gapFollowsPoll() {
        #expect(ChartSampling.breakGap(window: 300, limit: 180, pollInterval: 1) == 5)
        #expect(ChartSampling.breakGap(window: 300, limit: 180, pollInterval: 5) == 15)
    }
}
