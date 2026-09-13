import Foundation

/// The history's life across daemon restarts.
///
/// The history lived only in the daemon's memory, so every restart - and every
/// update of the daemon is one - started the chart from nothing. It is saved to
/// disk now and read back on start; this is the part of that which does not
/// touch a disk.
public enum HistoryRecord {
    /// The longest window the chart shows. Anything older is of no use to it.
    public static let maxAge: TimeInterval = 30 * 60

    /// What of a saved history is still worth having at `now`: inside the chart's
    /// longest window, not from the future (a clock that jumped back), in order,
    /// and no more of it than the history holds.
    public static func restorable(_ samples: [HistorySample], now: TimeInterval,
                                  maxAge: TimeInterval = maxAge, capacity: Int) -> [HistorySample] {
        let kept = samples
            .filter { $0.t > now - maxAge && $0.t <= now + 60 }
            .sorted { $0.t < $1.t }
        return Array(kept.suffix(max(capacity, 0)))
    }

    /// Values rounded to what anyone can see - a hundredth of a degree, a whole
    /// rpm - so a saved half hour is a few hundred kilobytes rather than the
    /// megabyte full float precision spells out.
    public static func compacted(_ samples: [HistorySample]) -> [HistorySample] {
        samples.map { sample in
            HistorySample(t: (sample.t * 100).rounded() / 100,
                          temps: sample.temps.mapValues { ($0 * 100).rounded() / 100 },
                          fanRPM: sample.fanRPM.map { $0.rounded() })
        }
    }
}

/// Why the control loop has not ticked for a while.
///
/// The watchdog used to see only a wall-clock gap, and a Mac that slept for an
/// hour looks exactly like a loop that hung for an hour: every wake was logged
/// as "control loop stalled for 3649s". The difference is in the clocks. Time
/// the machine spent awake has a clock that stops while it sleeps; if that one
/// barely moved, nothing hung - the Mac was asleep.
public enum LoopHealth: Equatable {
    case ticking
    /// The machine slept for about this long.
    case slept(TimeInterval)
    /// The loop really did stop, for this long of awake time.
    case stalled(TimeInterval)

    public static func classify(wallAge: TimeInterval, awakeAge: TimeInterval,
                                limit: TimeInterval) -> LoopHealth {
        if awakeAge > limit { return .stalled(awakeAge) }
        if wallAge > limit { return .slept(wallAge - awakeAge) }
        return .ticking
    }
}
