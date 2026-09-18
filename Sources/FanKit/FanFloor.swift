import Foundation

/// The slowest a fan will actually turn, learned from watching it.
///
/// `F<n>Mn` is the SMC's advertised minimum and not the truth: this project already
/// knew a fan asked for less than that keeps going, and on an M3 Pro a fan asked for
/// 446 rpm settled at 968. So every curve point between a stop and that figure draws a
/// speed the fan will not run at - the line says 600, the fan says 968, and the editor
/// is the only place that believes the 600.
///
/// The floor cannot be a number in a table. It belongs to the fan, and this project
/// does not keep per-model tables. It cannot be measured on demand either, because
/// measuring means spinning somebody's fans up and down to see where they give out,
/// which is not a thing to do to a person's machine to draw a dashed line.
///
/// So it is learned from work already being done. The daemon holds a fan at a speed
/// and reads back what the fan did, once a second, because it has to anyway. When the
/// reading settles above what was asked for, the fan has refused to go lower and has
/// said what its floor is.
public struct FanFloor: Codable, Sendable, Equatable {
    /// How far above the target the reading has to sit before it counts as a refusal
    /// rather than a fan on its way somewhere.
    static let refusalMargin = 120.0
    /// How still the reading has to be to count as settled.
    static let steadyBand = 70.0
    /// Consecutive seconds of stillness before a reading is believed. A fan coasting
    /// down from 5000 passes through every speed on the way, and each one of them
    /// looks like a floor for a moment.
    static let steadySeconds = 8
    /// Separate occasions before the answer is shown to anybody. One settled episode
    /// is a fan that happened to sit there; three are a fan that cannot go lower.
    static let episodesNeeded = 3

    private var recent: [Double] = []
    private var recentTarget: Double?
    private var creditedThisEpisode = false

    public private(set) var episodes = 0
    /// The lowest speed the fan was seen holding while being asked for less.
    public private(set) var learned: Double?

    public init() {}

    /// Believed once the fan has refused the same way more than once.
    public var isKnown: Bool { learned != nil && episodes >= Self.episodesNeeded }

    /// One reading, from a tick where the daemon was holding this fan.
    ///
    /// `held` is what makes a reading evidence at all: a fan the system is driving says
    /// nothing about what this one would do if asked.
    public mutating func observe(target: Double, actual: Double, held: Bool) {
        guard held, actual > 0, target >= 0 else { reset(); return }

        // A change of target starts a new episode: whatever the fan was settled at
        // before, it is now on its way somewhere else.
        if let previous = recentTarget, abs(previous - target) > 1 { reset() }
        recentTarget = target

        recent.append(actual)
        if recent.count > Self.steadySeconds { recent.removeFirst() }
        guard recent.count == Self.steadySeconds,
              let low = recent.min(), let high = recent.max(),
              high - low <= Self.steadyBand
        else { return }

        // Settled. It is only evidence of a floor if we asked for less and did not get
        // it; a fan doing exactly what it was told teaches nothing about how low it
        // goes, except that it goes at least this low.
        guard target + Self.refusalMargin < low else { return }
        if !creditedThisEpisode {
            episodes += 1
            creditedThisEpisode = true
        }
        learned = min(learned ?? .infinity, low)
    }

    private mutating func reset() {
        recent.removeAll()
        recentTarget = nil
        creditedThisEpisode = false
    }
}
