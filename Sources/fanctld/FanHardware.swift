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
            try takeManualMode(index)
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

    // MARK: Getting past the thermal manager

    /// Asks for manual control of a fan, unlocking it first if the firmware refuses.
    ///
    /// On an M1 the plain write is the whole story. From the M3 on, thermalmonitord
    /// holds the fans in mode 3 and the SMC answers a manual-mode write with status
    /// 0x82. Raising `Ftst` asks the thermal manager to stand down, and after some
    /// seconds it does - measured here at 7.6 and 12.6 seconds on two runs, against
    /// the 3 the research describes.
    ///
    /// One attempt per tick, not a tight retry loop. The retries are not what wins:
    /// nothing is being battered into submission, we are waiting for a daemon to let
    /// go and polling to notice when it has. A hundred and twenty writes a second
    /// achieve exactly what thirteen a second apart do, and the control loop has a
    /// watchdog that would fire long before a blocking retry finished.
    private func takeManualMode(_ index: Int) throws {
        do {
            try smc.write("F\(index)Md", value: 1)
            unlockDeadline = nil
            return
        } catch let error as SMCDevice.Failure {
            guard case .rejected(_, let status) = error, status == 0x82, hasTestKey else { throw error }
        }

        // Refused, and this Mac has the key that asks the thermal manager to let go.
        if unlockDeadline == nil {
            try? smc.write("Ftst", value: 1)
            unlockDeadline = Date().addingTimeInterval(Self.unlockTimeout)
        }
        do {
            try smc.write("F\(index)Md", value: 1)
            unlockDeadline = nil
        } catch {
            if let deadline = unlockDeadline, Date() > deadline {
                // It is not coming. Put the machine's own management back rather than
                // leaving it switched off while we wait for something that will not happen.
                releaseTestKey()
            }
            throw error
        }
    }

    /// How long to wait for the thermal manager after `Ftst` goes up. Generous against
    /// the 13 seconds measured, because the cost of waiting is a fan that has not sped
    /// up yet and the cost of giving up early is a feature that works on a fast day.
    private static let unlockTimeout: TimeInterval = 45
    private var unlockDeadline: Date?
    /// Whether this Mac has the key at all. Some M3s reportedly do not, and there the
    /// behaviour is what it always was.
    private lazy var hasTestKey = smc.read("Ftst") != nil

    /// Hands the machine's own thermal management back.
    ///
    /// Called on every path that stops holding a fan, because `Ftst` left raised is
    /// the Mac's automatic cooling left switched off - which is a far worse thing to
    /// leave behind than a fan stuck at one speed.
    func releaseTestKey() {
        unlockDeadline = nil
        guard hasTestKey else { return }
        guard (smc.read("Ftst")?.value ?? 0) != 0 else { return }
        try? smc.write("Ftst", value: 0)
    }

    /// Rounding in the SMC's own float, not a licence for it to pick another speed.
    private static let targetTolerance = 5.0
    private static let ignoredBeforeGivingUp = 3
    /// Consecutive writes the SMC accepted and discarded, per fan.
    private var ignoredWrites: [Int: Int] = [:]

    /// Gives a fan back to the system, but only one we actually took.
    ///
    /// The test key goes down whenever nothing is held, and that has to happen even
    /// on the early return. Losing a fan to the SMC drops it from `owned` without
    /// going through here, so the next call for that fan finds nothing to release and
    /// used to leave on the early return - with `Ftst` still raised and the Mac's own
    /// thermal management still switched off, by a daemon that had given up.
    func release(_ index: Int) throws {
        defer { if owned.isEmpty { releaseTestKey() } }
        guard owned.contains(index) else { return }
        try smc.write("F\(index)Md", value: 0)
        owned.remove(index)
        sinceAssert[index] = nil
    }

    /// Clears any forced state left behind by whoever ran before us - a previous run of
    /// this daemon, or another fan utility - so the daemon always starts from auto.
    /// Done once at startup and logged, never as part of the control loop.
    func clearForeignForcedState() -> [Int: Double] {
        // Including the test key, which a previous run that was killed rather than
        // asked to stop would have left raised - and with it the Mac's automatic
        // cooling switched off until something turned it back on.
        releaseTestKey()
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
        // Last, and unconditionally: whether or not every fan went back cleanly, the
        // machine's own thermal management must not be left switched off.
        releaseTestKey()
        return allReleased
    }
}
