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
        // The key, not the call. A write to F<n>Md that returns 0x82 has not
        // necessarily failed to do anything: the SMC refuses the write when the mode
        // is already 1, so re-asserting a mode we are holding came back as a refusal
        // and the daemon concluded it had never got control. It then never wrote a
        // target, and two fans it *was* holding sat at zero while the interface said
        // it was still taking them. Same lesson as the target, one key along: believe
        // what the controller reads back, not what the call returned.
        if manualModeHeld(index) { unlockDeadline = nil; return }

        do {
            try smc.write("F\(index)Md", value: 1)
        } catch let error as SMCDevice.Failure {
            guard case .rejected(_, let status) = error, status == 0x82, hasTestKey else { throw error }
        }
        if manualModeHeld(index) { unlockDeadline = nil; return }

        // Really refused, and this Mac has the key that asks the thermal manager to
        // let go.
        if unlockDeadline == nil {
            try? smc.write("Ftst", value: 1)
            raisedTestKey = true
            unlockDeadline = Date().addingTimeInterval(Self.unlockTimeout)
        }
        try? smc.write("F\(index)Md", value: 1)
        if manualModeHeld(index) { unlockDeadline = nil; return }

        if let deadline = unlockDeadline, Date() > deadline {
            // It is not coming. Put the machine's own management back rather than
            // leaving it switched off while we wait for something that will not happen.
            releaseTestKey()
        }
        throw SMCDevice.Failure.rejected(key: "F\(index)Md", status: 0x82)
    }

    /// Manual mode, as the controller has it rather than as we asked for it.
    private func manualModeHeld(_ index: Int) -> Bool { rawMode(index) == 1 }

    /// How long to wait for the thermal manager after `Ftst` goes up. Generous against
    /// the 13 seconds measured, because the cost of waiting is a fan that has not sped
    /// up yet and the cost of giving up early is a feature that works on a fast day.
    private static let unlockTimeout: TimeInterval = 45
    private var unlockDeadline: Date?
    /// Waiting for the thermal manager to let go. What separates "cannot" from
    /// "not yet", and the interface needs the difference more than the log does.
    var isAcquiring: Bool { unlockDeadline != nil }
    /// Whether this Mac has the key at all. Some M3s reportedly do not, and there the
    /// behaviour is what it always was.
    private lazy var hasTestKey = smc.read("Ftst") != nil

    /// Whether the key standing raised is ours.
    private var raisedTestKey = false

    /// Hands the machine's own thermal management back - ours, and only ours.
    ///
    /// Called on every path that stops holding a fan, because `Ftst` left raised is
    /// the Mac's automatic cooling left switched off, which is a far worse thing to
    /// leave behind than a fan stuck at one speed.
    ///
    /// Only if we raised it, though. This runs on every tick a fan is not held, and a
    /// daemon sitting in System mode was therefore clearing the key once a second -
    /// including a key raised by something else entirely, which is how it stopped a
    /// diagnostic running beside it from ever taking a fan. Clearing what another
    /// process is relying on is not this one's business; clearing what is left over
    /// from a dead one is, and that is `clearForeignForcedState` at startup.
    func releaseTestKey() {
        unlockDeadline = nil
        guard hasTestKey, raisedTestKey else { return }
        raisedTestKey = false
        guard (smc.read("Ftst")?.value ?? 0) != 0 else { return }
        if !smc.writeAndVerify("Ftst", value: 0) {
            Log.error("Ftst is still raised: the Mac's own thermal management is off")
        }
    }

    /// Drops the key whoever raised it. Startup only: at that point anything raised is
    /// either a previous run of this daemon that was killed, or a tool long gone, and
    /// in both cases the machine is cooling itself by nobody's rules.
    func clearAnyTestKey() {
        raisedTestKey = false
        unlockDeadline = nil
        guard hasTestKey, (smc.read("Ftst")?.value ?? 0) != 0 else { return }
        if !smc.writeAndVerify("Ftst", value: 0) {
            Log.error("Ftst is still raised: the Mac's own thermal management is off")
        }
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
        // Verified, because handing a fan back is the half of this that must not fail
        // quietly. The mode key can take a moment to settle, and the system writes into
        // it too, so a single write and an immediate read disagree often enough to
        // matter. Ownership is dropped either way: we are not holding it any more, and
        // claiming otherwise would stop the next release from trying again.
        owned.remove(index)
        sinceAssert[index] = nil
        guard smc.writeAndVerify("F\(index)Md", value: 0) else {
            throw SMCDevice.Failure.ignored(key: "F\(index)Md", asked: 0,
                                            kept: rawMode(index) ?? .nan)
        }
    }

    /// Clears any forced state left behind by whoever ran before us - a previous run of
    /// this daemon, or another fan utility - so the daemon always starts from auto.
    /// Done once at startup and logged, never as part of the control loop.
    func clearForeignForcedState() -> [Int: Double] {
        // Including the test key, which a previous run that was killed rather than
        // asked to stop would have left raised - and with it the Mac's automatic
        // cooling switched off until something turned it back on.
        clearAnyTestKey()
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
