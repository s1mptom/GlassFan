import Foundation
import FanKit

/// The fans this Mac actually has, and the only place that writes to them.
///
/// Control is tracked here rather than read back from the SMC. The mode key is not a
/// plain "forced" flag - on this hardware the system writes its own values into it
/// (3 was observed while the fans were idle and stopped), so inferring ownership from
/// it would have us fighting the system. We only ever release what we ourselves took.
final class FanHardware {
    struct Fan {
        let index: Int
        let limits: FanLimits
    }

    private let smc: SMCDevice
    private(set) var fans: [Fan] = []
    /// Fans this daemon has taken control of.
    private var owned: Set<Int> = []
    /// Ticks since forced mode was last re-asserted, per fan.
    private var sinceAssert: [Int: Int] = [:]
    private let reassertEvery = 10

    init(smc: SMCDevice) {
        self.smc = smc
        discover()
    }

    private func discover() {
        guard let count = smc.read("FNum")?.value else { return }
        fans = (0..<Int(count)).compactMap { index in
            guard let minRPM = smc.read("F\(index)Mn")?.value,
                  let maxRPM = smc.read("F\(index)Mx")?.value,
                  maxRPM > minRPM else { return nil }
            return Fan(index: index, limits: FanLimits(minRPM: minRPM, maxRPM: maxRPM))
        }
    }

    func actualRPM(_ index: Int) -> Double? { smc.read("F\(index)Ac")?.value }
    func targetRPM(_ index: Int) -> Double? { smc.read("F\(index)Tg")?.value }

    /// Whether this daemon is holding the fan. Not a reading of the SMC mode key.
    func isOwned(_ index: Int) -> Bool { owned.contains(index) }

    /// Raw mode byte, for diagnostics only.
    func rawMode(_ index: Int) -> Double? { smc.read("F\(index)Md")?.value }

    /// Holds a fan at `rpm`. Forced mode is re-asserted periodically because sleep and
    /// wake can hand control back to the system behind our back.
    ///
    /// The target is read back afterwards, because a write returning `SMC_OK` does not
    /// mean the SMC kept it. Measured on an M3 Pro: with both fans set to a fixed
    /// maximum, `F0Md` sat at 3 and `F0Tg` at 0 while this wrote 1 and 5349 into them
    /// every second, every write succeeding and the fans stopped. Without the read
    /// back, the daemon reported that it was holding both fans and the interface said
    /// "fixed, 5349 rpm" over a machine whose fans were not turning - the one thing
    /// this code is otherwise careful never to do.
    func setTarget(_ index: Int, rpm: Double) throws {
        let ticks = sinceAssert[index] ?? reassertEvery
        if !owned.contains(index) || ticks >= reassertEvery {
            try smc.write("F\(index)Md", value: 1)
            sinceAssert[index] = 0
        } else {
            sinceAssert[index] = ticks + 1
        }
        try smc.write("F\(index)Tg", value: rpm)

        // A single mismatch is not a verdict: the system writes into these keys too,
        // and one tick can land between our write and its own. Three in a row is the
        // SMC keeping its own value, not a race.
        let kept = targetRPM(index) ?? .nan
        guard abs(kept - rpm) > Self.targetTolerance else {
            ignoredWrites[index] = 0
            owned.insert(index)
            return
        }
        let misses = (ignoredWrites[index] ?? 0) + 1
        ignoredWrites[index] = misses
        guard misses >= Self.ignoredBeforeGivingUp else {
            owned.insert(index)
            return
        }
        // Nothing was taken, so there is nothing to give back later either.
        owned.remove(index)
        sinceAssert[index] = nil
        throw SMCDevice.Failure.ignored(key: "F\(index)Tg", asked: rpm, kept: kept)
    }

    /// Rounding in the SMC's own float, not a licence for it to pick another speed.
    private static let targetTolerance = 5.0
    private static let ignoredBeforeGivingUp = 3
    /// Consecutive writes the SMC accepted and discarded, per fan.
    private var ignoredWrites: [Int: Int] = [:]

    /// Gives a fan back to the system, but only one we actually took.
    func release(_ index: Int) throws {
        guard owned.contains(index) else { return }
        try smc.write("F\(index)Md", value: 0)
        owned.remove(index)
        sinceAssert[index] = nil
    }

    /// Clears any forced state left behind by whoever ran before us - a previous run of
    /// this daemon, or another fan utility - so the daemon always starts from auto.
    /// Done once at startup and logged, never as part of the control loop.
    func clearForeignForcedState() -> [Int: Double] {
        var found: [Int: Double] = [:]
        for fan in fans {
            guard let mode = rawMode(fan.index), mode != 0 else { continue }
            found[fan.index] = mode
            try? smc.write("F\(fan.index)Md", value: 0)
        }
        owned.removeAll()
        sinceAssert.removeAll()
        return found
    }

    @discardableResult
    func releaseAll() -> Bool {
        var allReleased = true
        for index in owned {
            do { try release(index) } catch { allReleased = false }
        }
        return allReleased
    }
}
