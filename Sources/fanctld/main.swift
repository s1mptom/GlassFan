import Foundation
import FanKit

/// Signal sources for the hardware experiments below, and the flag they raise.
///
/// At the top of the file because top-level `var`s in main.swift are initialised in
/// the order the file executes, not the order it reads: one of these declared below
/// its first use is not an empty array, it is uninitialised memory, and appending to
/// it crashes. The queue is its own because the experiments spend their time asleep
/// on the main thread, where a source scheduled on the main queue would never fire.
var minimumTestSignals: [DispatchSourceSignal] = []
let minimumTestSignalQueue = DispatchQueue(label: "glassfan.experiments.signals")

/// A flag one thread raises and another reads. Small enough to hand-roll, and the
/// alternative - a plain Bool across two threads - is the kind of race that works
/// every time it is tried and fails the once it matters.
final class ManagedAtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func raise() { lock.lock(); value = true; lock.unlock() }
    var isRaised: Bool { lock.lock(); defer { lock.unlock() }; return value }
}


// A probe mode that needs no root, so the hardware can be inspected before installing.
/// Hardware experiment: what does the SMC do with a target below F?Mn? Writes a
/// descending set of targets to each fan, reads back the actual rpm and what the
/// SMC kept as the target, and releases the fan to the system afterwards
/// whatever happens. Run with the daemon stopped, or the two will argue.
if CommandLine.arguments.contains("--stop-test") {
    do {
        let smc = try SMCDevice()
        let hardware = FanHardware(smc: smc)
        func line(_ fan: Int, _ label: String) {
            print(String(format: "  fan %d  %-14@ actual %5.0f   target kept %5.0f   mode %.0f",
                         fan, label,
                         hardware.actualRPM(fan) ?? -1,
                         hardware.targetRPM(fan) ?? -1,
                         hardware.rawMode(fan) ?? -1))
            fflush(stdout)
        }
        for fan in hardware.fans {
            let i = fan.index
            print(String(format: "fan %d: SMC limits %.0f-%.0f", i, fan.limits.minRPM, fan.limits.maxRPM))
            line(i, "before")
            defer { try? hardware.release(i); line(i, "released") }
            for target in [1000.0, 500.0, 0.0] {
                do {
                    try hardware.setTarget(i, rpm: target)
                } catch {
                    print("  fan \(i)  write \(Int(target)) REFUSED: \(error)")
                    continue
                }
                Thread.sleep(forTimeInterval: 5)
                line(i, "asked \(Int(target))")
            }
        }
    } catch {
        print("stop-test failed: \(error)")
        exit(1)
    }
    exit(0)
}

/// Hardware experiment, part two: is a fan *stable* below the declared minimum,
/// or does it hunt - stop, restart, stop? Holds each of a few sub-minimum
/// targets for a while, samples the actual rpm every second, and reports the
/// spread and every stop and restart seen. Releases the fan afterwards.
if CommandLine.arguments.contains("--stall-test") {
    do {
        let smc = try SMCDevice()
        let hardware = FanHardware(smc: smc)
        let hold = 40
        for fan in hardware.fans {
            let i = fan.index
            print(String(format: "fan %d (SMC minimum %.0f)", i, fan.limits.minRPM))
            defer { try? hardware.release(i) }
            for target in [1300.0, 1000.0, 600.0] {
                try hardware.setTarget(i, rpm: target)
                var samples: [Double] = []
                var stops = 0, restarts = 0
                var wasRunning = false
                for _ in 0..<hold {
                    Thread.sleep(forTimeInterval: 1)
                    let rpm = hardware.actualRPM(i) ?? -1
                    samples.append(rpm)
                    let running = rpm > 0
                    if wasRunning && !running { stops += 1 }
                    if !wasRunning && running && !samples.dropLast().isEmpty { restarts += 1 }
                    wasRunning = running
                }
                let settled = Array(samples.suffix(hold - 10))   // after spin-up
                let lo = settled.min() ?? 0, hi = settled.max() ?? 0
                let mean = settled.reduce(0, +) / Double(max(settled.count, 1))
                let trace = samples.enumerated().filter { $0.offset % 4 == 0 }
                    .map { String(format: "%.0f", $0.element) }.joined(separator: " ")
                print(String(format: "  target %4.0f  settled min %4.0f  max %4.0f  mean %4.0f  stops %d  restarts %d",
                             target, lo, hi, mean, stops, restarts))
                print("           every 4s: \(trace)")
                fflush(stdout)
            }
        }
    } catch {
        print("stall-test failed: \(error)")
        exit(1)
    }
    exit(0)
}

/// Every temperature key this Mac reports, as tab-separated key, SMC type,
/// value, group and current display name - sorted by key, for naming work.
/// Read-only; needs no privileges.
if CommandLine.arguments.contains("--dump-sensors") {
    do {
        let smc = try SMCDevice()
        let temperatures = smc.temperatureReadings()
        // Names for the parts no table covers come from this machine's key layout,
        // so the catalogue is told what this machine reports before anything is
        // named - exactly as the daemon does it.
        SensorCatalog.configure(temperatures.map { SensorReading(key: $0.key, value: $0.value) })
        // In list order, essential sensors marked: the table the interface shows.
        for (key, type, value) in temperatures.sorted(by: { SensorCatalog.precedes($0.key, $1.key) }) {
            let info = SensorCatalog.info(for: key)
            print("\(key)\t\(type)\t\(String(format: "%.1f", value))\t\(info.group.rawValue)\t\(info.essential ? "*" : "")\t\(info.name)")
        }
        for (zone, key, target) in smc.zoneTargets() {
            let name = SensorCatalog.smcZoneName(zone)
            print("\(key)\tflt \t\(String(format: "%.1f", target))\t-\t\t" +
                  L10n.t("Уставка SMC · \(name)", "SMC setpoint · \(name)"))
        }
        exit(0)
    } catch {
        print("dump failed: \(error)")
        exit(1)
    }
}

/// Watches the machine and reports which engine each sensor answers to, the way the
/// daemon learns it - but out loud, and over minutes rather than the daemon's much
/// longer bar.
///
/// Watches. It puts no load on the machine and never will: the whole point of
/// reading the power meters is that ordinary use already moves the engines apart, so
/// nothing has to be heated on purpose to find out what is where. Whatever you were
/// going to do with the Mac anyway is the experiment. Read-only, no privileges.
if let index = CommandLine.arguments.firstIndex(of: "--learn") {
    let seconds = Int(CommandLine.arguments.dropFirst(index + 1).first ?? "") ?? 300
    do {
        let smc = try SMCDevice()
        guard let power = PowerReport() else {
            print("IOReport is not available on this macOS, so engines cannot be learned")
            exit(1)
        }
        var affinity = EngineAffinity()
        print("watching for \(seconds)s, adding no load of its own - just use the Mac")
        var last = Date()
        for remaining in stride(from: seconds, to: 0, by: -1) {
            Thread.sleep(forTimeInterval: 1)
            let now = Date()
            var temperatures: [String: Double] = [:]
            for reading in smc.temperatureReadings() { temperatures[reading.key] = reading.value }
            affinity.observe(power: power.sinceLastReading(), temperatures: temperatures,
                             interval: now.timeIntervalSince(last))
            last = now
            if remaining % 30 == 0 {
                print("  \(remaining)s to go, \(affinity.sampleCount) samples")
                fflush(stdout)
            }
        }
        let verdicts = affinity.verdicts(minimumSamples: 60)
        print("\n\(verdicts.count) of \(affinity.sampleCount > 0 ? smc.temperatureReadings().count : 0) sensors attributed\n")
        print("key     engine    share   fit   name")
        for (key, verdict) in verdicts.sorted(by: { SensorCatalog.precedes($0.key, $1.key) }) {
            print(String(format: "%-6s  %-8s  %4.0f%%  %4.2f  %@", (key as NSString).utf8String!,
                         (verdict.engine.rawValue as NSString).utf8String!,
                         verdict.share * 100, verdict.fit, SensorCatalog.info(for: key).name))
        }
        exit(0)
    } catch {
        print("learn failed: \(error)")
        exit(1)
    }
}

/// Proves a takeover rather than assuming one.
///
///     fanctld --takeover-test [rpm]
///
/// Seeing a fan at the speed that was asked for is suggestive and not proof: the SMC
/// might have wanted it spinning anyway. So this drives the machine cold, hands the
/// fans back, waits until the SMC has stopped them of its own accord - the state where
/// nothing used to work - and only then asks for a speed. A fan that goes from the
/// system's own zero to a number nobody else had a reason to pick was taken from it.
///
/// One process, and it starts no daemons. The first version of this orchestrated three
/// of them with a shell script, killed them by matching an environment variable that
/// `pkill -f` cannot see, and left all three running as root fighting over the same
/// keys - which is exactly the failure this code is otherwise built to avoid, arrived
/// at through the test for it. It also ran `launchctl bootout` and could not put the
/// service back. Nothing here touches launchd or spawns anything.
///
/// It drives `FanHardware`, not a copy of it, so what passes here is what the daemon
/// does. Set both fans to System in GlassFan first: the daemon writes nothing in that
/// mode, and two writers is the thing being avoided.
if CommandLine.arguments.contains("--takeover-test") {
    let arguments = CommandLine.arguments.drop { $0 != "--takeover-test" }.dropFirst()
    let wanted = Double(arguments.first ?? "") ?? 2600
    guard getuid() == 0 else { print("--takeover-test needs root"); exit(1) }
    do {
        let smc = try SMCDevice()
        let hardware = FanHardware(smc: smc)
        guard let fan = hardware.fans.first else { print("no fans found"); exit(1) }
        let index = fan.index

        if let mode = smc.read("F\(index)Md")?.value, mode == 1 {
            print("F\(index)Md is 1: something already holds this fan.")
            print("Set both fans to System in GlassFan and run this again.")
            exit(0)
        }

        let restoreLock = NSLock()
        var done = false
        func restore() {
            restoreLock.lock(); defer { restoreLock.unlock() }
            guard !done else { return }
            done = true
            hardware.releaseAll()
            // Verified, and in this order: manual mode goes first, then the unlock.
            // The old restore wrote both and read them back in the same breath, saw
            // the values it had just replaced, and announced a failure that had not
            // happened.
            let modeBack = smc.writeAndVerify("F\(index)Md", value: 0)
            let testBack = smc.read("Ftst") == nil || smc.writeAndVerify("Ftst", value: 0)
            print(String(format: "restored: F%dMd %.0f, Ftst %.0f%@",
                         index, smc.read("F\(index)Md")?.value ?? -1,
                         smc.read("Ftst")?.value ?? -1,
                         modeBack && testBack ? "" : "   ← NOT FULLY RESTORED, run --clear-lock"))
            fflush(stdout)
        }
        func finish(_ code: Int32) -> Never { restore(); exit(code) }
        let stop = ManagedAtomicFlag()
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: minimumTestSignalQueue)
            source.setEventHandler { stop.raise() }
            source.resume()
            minimumTestSignals.append(source)
        }
        func zone() -> Double { smc.read("TCDX")?.value ?? -1 }
        func rpm() -> Double { hardware.actualRPM(index) ?? -1 }
        func mode() -> Double { hardware.rawMode(index) ?? -1 }
        /// Holds the fan for `seconds`, re-asserting each second the way the control
        /// loop does - the unlock needs several passes before it takes.
        func hold(_ target: Double, seconds: Int, label: String) {
            for second in 1...seconds {
                if stop.isRaised { print("interrupted"); finish(1) }
                do { try hardware.setTarget(index, rpm: target) }
                catch { if second % 10 == 0 { print("  \(label) t+\(second)s: \(error)") } }
                Thread.sleep(forTimeInterval: 1)
                if second % 10 == 0 {
                    print(String(format: "  %@ t+%3ds  %.0f rpm  F%dMd %.0f  TCDX %.1f",
                                 label, second, rpm(), index, mode(), zone()))
                    fflush(stdout)
                }
            }
        }

        print("=== 1. cooling: fan \(index) at maximum for 90s ===")
        hold(fan.limits.maxRPM, seconds: 90, label: "cool")

        print("=== 2. handing back, then waiting for the SMC to stop it by itself ===")
        hardware.releaseAll()
        try? smc.write("F\(index)Md", value: 0)
        var stopped = false
        for elapsed in stride(from: 0, to: 600, by: 5) {
            if stop.isRaised { print("interrupted"); finish(1) }
            Thread.sleep(forTimeInterval: 5)
            if rpm() == 0 {
                print("  stopped by the system after \(elapsed + 5)s")
                print(String(format: "  PROOF  F%dMd %.0f   F%dTg %.0f   Ftst %.0f   %.0f rpm   TCDX %.1f",
                             index, mode(), index, hardware.targetRPM(index) ?? -1,
                             smc.read("Ftst")?.value ?? -1, rpm(), zone()))
                stopped = true
                break
            }
            if elapsed % 60 == 0 {
                print(String(format: "  wait t+%3ds  %.0f rpm  F%dMd %.0f  TCDX %.1f",
                             elapsed, rpm(), index, mode(), zone()))
                fflush(stdout)
            }
        }
        guard stopped else {
            print("  it never stopped; the machine is too busy to be a fair test")
            finish(0)
        }

        print("=== 3. asking for \(Int(wanted)) rpm from that stopped state ===")
        hold(wanted, seconds: 60, label: "take")
        let settled = rpm()
        print(String(format: "result: %.0f rpm against %.0f asked, F%dMd %.0f",
                     settled, wanted, index, mode()))
        print(abs(settled - wanted) < 250 && mode() == 1
              ? "TAKEOVER: the fan went from the system's own zero to the speed asked for"
              : "NOT TAKEN: the fan did not reach the speed asked for")
        finish(0)
    } catch {
        print("takeover-test failed: \(error)")
        exit(1)
    }
}

/// Puts the machine's own thermal management back, whatever left it switched off.
///
/// `Ftst` raised is the Mac cooling itself by nobody's rules. The daemon clears it on
/// every path it controls, but a process killed outright controls no paths, so there
/// has to be a way to say "give it back" that does not depend on the thing that took
/// it still being alive.
if CommandLine.arguments.contains("--clear-lock") {
    guard getuid() == 0 else { print("--clear-lock needs root"); exit(1) }
    do {
        let smc = try SMCDevice()
        let count = Int(smc.read("FNum")?.value ?? 0)
        for index in 0..<count {
            if let mode = smc.read("F\(index)Md")?.value, mode == 1 {
                let ok = smc.writeAndVerify("F\(index)Md", value: 0)
                print("fan \(index): manual mode dropped\(ok ? "" : " - FAILED, it still reads 1")")
            }
        }
        if let test = smc.read("Ftst")?.value {
            if test != 0 {
                let ok = smc.writeAndVerify("Ftst", value: 0)
                print(String(format: "Ftst was %.0f, now %.0f%@", test,
                             smc.read("Ftst")?.value ?? -1,
                             ok ? "" : "   ← STILL RAISED, the thermal management is off"))
            } else {
                print("Ftst is already 0: the system has its thermal management")
            }
        } else {
            print("no Ftst key on this Mac; nothing to clear")
        }
        exit(0)
    } catch {
        print("clear-lock failed: \(error)")
        exit(1)
    }
}

/// Hardware experiment: the documented way past thermalmonitord on M3 and later.
///
///     fanctld --unlock-test [rpm] [seconds]
///
/// On an M1, writing 1 into `F<n>Md` takes the fan and that is the end of it. From the
/// M3 on, thermalmonitord holds the fans in mode 3 and the firmware answers a
/// manual-mode write with status 0x82. The sequence that reportedly gets past it, from
/// agoodkind/macos-smc-fan, which had it out of thermalmonitord and AppleSMC.kext:
/// ask for manual mode; if refused, write 1 into `Ftst`, give the thermal manager a
/// few seconds to let go, and keep asking.
///
/// Everything is put back on the way out - mode to 0, `Ftst` to 0 - because `Ftst`
/// left at 1 is the machine's own thermal management left switched off.
if CommandLine.arguments.contains("--unlock-test") {
    let arguments = CommandLine.arguments.drop { $0 != "--unlock-test" }.dropFirst()
    let wanted = Double(arguments.first ?? "") ?? 3000
    let seconds = Int(arguments.dropFirst().first ?? "") ?? 25
    guard getuid() == 0 else { print("--unlock-test needs root"); exit(1) }
    do {
        let smc = try SMCDevice()
        let hasFtst = smc.read("Ftst") != nil
        print(String(format: "before: F0Md %.0f, F0Tg %.0f, fan0 %.0f rpm, Ftst %@",
                     smc.read("F0Md")?.value ?? -1, smc.read("F0Tg")?.value ?? -1,
                     smc.read("F0Ac")?.value ?? -1,
                     hasFtst ? String(format: "%.0f", smc.read("Ftst")?.value ?? -1) : "absent"))

        let restoreLock = NSLock()
        var alreadyRestored = false
        func restore() {
            restoreLock.lock()
            defer { restoreLock.unlock() }
            guard !alreadyRestored else { return }
            alreadyRestored = true
            try? smc.write("F0Md", value: 0)
            if hasFtst { try? smc.write("Ftst", value: 0) }
            print(String(format: "restored: F0Md %.0f, Ftst %@, fan0 %.0f rpm",
                         smc.read("F0Md")?.value ?? -1,
                         hasFtst ? String(format: "%.0f", smc.read("Ftst")?.value ?? -1) : "absent",
                         smc.read("F0Ac")?.value ?? -1))
            fflush(stdout)
        }
        func finish(_ code: Int32) -> Never { restore(); exit(code) }

        let stop = ManagedAtomicFlag()
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: minimumTestSignalQueue)
            source.setEventHandler { stop.raise() }
            source.resume()
            minimumTestSignals.append(source)
        }

        /// Manual mode taken, or not. Reports what the firmware said rather than
        /// whether the call returned, which is the distinction this whole thing turns on.
        func takeManualMode() -> Bool {
            do {
                try smc.write("F0Md", value: 1)
                return (smc.read("F0Md")?.value ?? -1) == 1
            } catch {
                print("  F0Md = 1 refused: \(error)")
                return false
            }
        }

        print("asking for manual mode the plain way")
        var taken = takeManualMode()
        if !taken {
            guard hasFtst else {
                print("no Ftst key on this Mac, so there is nothing else to try")
                finish(0)
            }
            print("writing Ftst = 1 and waiting for the thermal manager to let go")
            do { try smc.write("Ftst", value: 1) }
            catch { print("  Ftst = 1 refused: \(error)"); finish(0) }
            print(String(format: "  Ftst now reads %.0f", smc.read("Ftst")?.value ?? -1))
            for attempt in 1...300 {
                if stop.isRaised { print("interrupted"); finish(1) }
                Thread.sleep(forTimeInterval: 0.1)
                if takeManualMode() { print("  manual mode taken after \(attempt) tries"); taken = true; break }
                if attempt % 50 == 0 { print("  still trying (\(attempt))"); fflush(stdout) }
            }
        }
        guard taken else {
            print("manual mode never taken - the SMC held on through the whole sequence")
            finish(0)
        }

        print(String(format: "manual mode is ours. Asking for %.0f rpm", wanted))
        do { try smc.write("F0Tg", value: wanted) }
        catch { print("  F0Tg refused: \(error)"); finish(0) }
        for second in 1...seconds {
            Thread.sleep(forTimeInterval: 1)
            if stop.isRaised { print("interrupted"); finish(1) }
            print(String(format: "  t+%2ds  fan0 %.0f rpm   F0Tg %.0f   F0Md %.0f   TCDX %.1f",
                         second, smc.read("F0Ac")?.value ?? -1, smc.read("F0Tg")?.value ?? -1,
                         smc.read("F0Md")?.value ?? -1, smc.read("TCDX")?.value ?? -1))
            fflush(stdout)
        }
        finish(0)
    } catch {
        print("unlock-test failed: \(error)")
        exit(1)
    }
}

/// Hardware experiment: does this SMC key take a value, and what happens if it does?
///
///     fanctld --write-test <key> <value> [seconds]
///
/// Reads the key, writes the value, reads it back, watches the fans for a while and
/// puts the original back on every way out. The same harness `--minimum-test` uses,
/// pointed wherever the next question is.
///
/// Answering "is it writable" needs the read-back, not the write: on this hardware a
/// write to a key the SMC has its own opinion about returns success and changes
/// nothing. `F0Tg` and `F0Mn` both do it.
///
/// Restricted to the keys these experiments are about. A root process that will write
/// any four characters it is handed into the controller that runs the fans and the
/// charger is not a diagnostic, it is a loaded gun, and the list costs one line.
let writeTestAllowed: Set<String> = [
    "F0Mn", "F1Mn", "F0Mx", "F1Mx", "F0Tg", "F1Tg", "F0Md", "F1Md",
    "Tf16", "Tf26",   // the SMC's own setpoints, the one lever left worth trying
]

if let index = CommandLine.arguments.firstIndex(of: "--write-test") {
    let arguments = CommandLine.arguments.dropFirst(index + 1)
    guard let key = arguments.first, let value = Double(arguments.dropFirst().first ?? "") else {
        print("usage: fanctld --write-test <key> <value> [seconds]")
        exit(1)
    }
    let seconds = Int(arguments.dropFirst(2).first ?? "") ?? 20
    // The key is checked before the privileges are, so a typo is caught by anyone
    // running this rather than only by whoever remembered to put sudo in front.
    guard writeTestAllowed.contains(key) else {
        print("\(key) is not one of the keys this is allowed to write: "
              + writeTestAllowed.sorted().joined(separator: ", "))
        exit(1)
    }
    guard getuid() == 0 else { print("--write-test needs root"); exit(1) }
    do {
        let smc = try SMCDevice()
        guard let original = smc.read(key)?.value else {
            print("\(key) is not readable on this Mac")
            exit(1)
        }
        // A setpoint is the temperature the machine cools itself to. Lowering one asks
        // for more cooling and is the safe direction; raising one asks the Mac to run
        // hotter than Apple decided it should, which is not a thing to find out by
        // accident at three in the afternoon.
        if key.hasPrefix("Tf"), value > original {
            print(String(format: "refusing to raise a thermal setpoint: %@ is %.1f and you asked for %.1f",
                         key, original, value))
            exit(1)
        }
        print(String(format: "%@ is %.2f; writing %.2f", key, original, value))

        let restoreLock = NSLock()
        var alreadyRestored = false
        func restore() {
            restoreLock.lock()
            defer { restoreLock.unlock() }
            guard !alreadyRestored else { return }
            alreadyRestored = true
            try? smc.write(key, value: original)
            let back = smc.read(key)?.value ?? -1
            if abs(back - original) <= 0.5 {
                print(String(format: "restored: %@ is %.2f again", key, back))
            } else {
                print(String(format: "!! %@ is %.2f and should be %.2f - set it back by hand",
                             key, back, original))
            }
            fflush(stdout)
        }
        func finish(_ code: Int32) -> Never { restore(); exit(code) }

        let stop = ManagedAtomicFlag()
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: minimumTestSignalQueue)
            source.setEventHandler { stop.raise() }
            source.resume()
            minimumTestSignals.append(source)
        }

        do { try smc.write(key, value: value) }
        catch { print("refused outright: \(error)"); finish(0) }

        let kept = smc.read(key)?.value ?? -1
        guard abs(kept - value) <= 0.5 else {
            print(String(format: "the SMC kept %.2f: %@ is not writable", kept, key))
            finish(0)
        }
        print("the SMC kept it. Watching:")
        for second in 1...seconds {
            Thread.sleep(forTimeInterval: 1)
            if stop.isRaised { print("interrupted"); finish(1) }
            print(String(format: "  t+%2ds  fan0 %.0f rpm  fan1 %.0f rpm  F0Tg %.0f  F0Md %.0f  TCDX %.1f  %@ %.2f",
                         second,
                         smc.read("F0Ac")?.value ?? -1, smc.read("F1Ac")?.value ?? -1,
                         smc.read("F0Tg")?.value ?? -1, smc.read("F0Md")?.value ?? -1,
                         smc.read("TCDX")?.value ?? -1,
                         key, smc.read(key)?.value ?? -1))
            fflush(stdout)
        }
        finish(0)
    } catch {
        print("write-test failed: \(error)")
        exit(1)
    }
}

/// Hardware experiment: is the fan's *minimum* a way in where its target is not?
///
/// On an M3 Pro the SMC discards whatever goes into `F0Tg` and keeps its own demand -
/// zero when it wants the fan stopped, `F0Mn` when it wants it idling. So the question
/// is whether `F0Mn` itself can be moved. If it can, the SMC's own floor rises, and the
/// SMC's value is the one that always wins.
///
/// Raises fan 0's minimum, watches, and puts it back. One fan, because one is enough to
/// learn the answer and half the noise.
///
/// Restoring is the part that has to work, so it is done by hand on every way out
/// rather than by `defer`: this block leaves through `exit`, and `exit` does not run
/// deferred code. A `defer { restore() }` here read as a safety net and was not one -
/// on the path that actually writes to the key, it would never have fired.
///
if CommandLine.arguments.contains("--minimum-test") {
    guard getuid() == 0 else {
        print("--minimum-test needs root: sudo fanctld --minimum-test")
        exit(1)
    }
    do {
        let smc = try SMCDevice()
        guard let original = smc.read("F0Mn")?.value else {
            print("F0Mn is not readable on this Mac; nothing to test")
            exit(1)
        }
        print(String(format: "F0Mn is %.0f, F0Tg %.0f, fan 0 at %.0f rpm",
                     original, smc.read("F0Tg")?.value ?? -1, smc.read("F0Ac")?.value ?? -1))

        // Wired up before anything is written, and idempotent, because the signal
        // handler and the ordinary path can both reach it.
        let restored = NSLock()
        var alreadyRestored = false
        func restore() {
            restored.lock()
            defer { restored.unlock() }
            guard !alreadyRestored else { return }
            alreadyRestored = true
            try? smc.write("F0Mn", value: original)
            let back = smc.read("F0Mn")?.value ?? -1
            if abs(back - original) <= 1 {
                print(String(format: "restored: F0Mn is %.0f again", back))
            } else {
                print(String(format: "!! F0Mn is %.0f and should be %.0f - set it back by hand", back, original))
            }
            fflush(stdout)
        }
        func finish(_ code: Int32) -> Never {
            restore()
            exit(code)
        }
        // The handler only raises a flag. Restoring from its own thread would have it
        // writing to the SMC while this one is part-way through a read of it, and
        // nothing below here serialises the two. The wait costs at most the second
        // the main thread is asleep for.
        let interrupted = ManagedAtomicFlag()
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: minimumTestSignalQueue)
            source.setEventHandler { interrupted.raise() }
            source.resume()
            minimumTestSignals.append(source)
        }

        // A fan somebody else is already forcing tells us nothing: its speed is theirs,
        // not the SMC's answer to a raised floor. Better to say so than to hand back a
        // reading that cannot be interpreted.
        if let mode = smc.read("F0Md")?.value, mode == 1 {
            print("F0Md is 1: something is holding fan 0 already (the daemon, in Fixed or Curve).")
            print("Set both fans to System in GlassFan and run this again.")
            finish(0)
        }

        // With --wait, sit until the SMC is spinning the fan of its own accord.
        //
        // Worth the wait because of what the first run of this test could not tell
        // apart. It wrote to F0Mn while the fan was stopped, and the SMC kept its own
        // 1350 - but in that state the SMC keeps its own value for *every* key, the
        // target included, so "the minimum is not writable" and "nothing is writable
        // right now" look identical. The answer only means something asked inside the
        // window where the SMC does accept a write.
        //
        // And if the floor does stick there, it is the whole game: a minimum the SMC
        // carries with it as the machine cools is a minimum it cannot drop to zero
        // under.
        if CommandLine.arguments.contains("--wait") {
            print("waiting for the SMC to spin the fan on its own (F0Md 0, rpm above zero)")
            var waited = 0
            while true {
                let mode = smc.read("F0Md")?.value ?? -1
                let rpm = smc.read("F0Ac")?.value ?? 0
                if mode == 0, rpm > 0 {
                    print(String(format: "  window open after %d:%02d - fan 0 at %.0f rpm, F0Md %.0f",
                                 waited / 60, waited % 60, rpm, mode))
                    break
                }
                if interrupted.isRaised { print("interrupted while waiting"); finish(1) }
                if waited % 60 == 0 {
                    print(String(format: "  %d:%02d   %.0f rpm   F0Md %.0f   TCDX %.1f",
                                 waited / 60, waited % 60, rpm, mode,
                                 smc.read("TCDX")?.value ?? -1))
                    fflush(stdout)
                }
                Thread.sleep(forTimeInterval: 2)
                waited += 2
            }
        }

        // If F0Mx cannot be read the ceiling falls back to the original, and writing
        // the original back is a test that proves nothing while looking like it passed.
        guard let ceiling = smc.read("F0Mx")?.value, ceiling > original + 100 else {
            print("F0Mx is not readable, or leaves no room above the minimum; nothing to test")
            finish(0)
        }
        let raised = min(original + 1150, ceiling)
        print(String(format: "writing F0Mn = %.0f", raised))
        do {
            try smc.write("F0Mn", value: raised)
        } catch {
            print("F0Mn refused the write outright: \(error)")
            finish(0)
        }
        let kept = smc.read("F0Mn")?.value ?? -1
        if abs(kept - raised) > 1 {
            print(String(format: "the SMC kept %.0f: the minimum is not writable either", kept))
            finish(0)
        }
        print("the SMC kept it. Watching what the fan does:")
        for second in 1...15 {
            Thread.sleep(forTimeInterval: 1)
            if interrupted.isRaised { print("interrupted"); finish(1) }
            print(String(format: "  t+%2ds  %.0f rpm   F0Tg %.0f   F0Md %.0f",
                         second, smc.read("F0Ac")?.value ?? -1,
                         smc.read("F0Tg")?.value ?? -1, smc.read("F0Md")?.value ?? -1))
            fflush(stdout)
        }
        finish(0)
    } catch {
        print("minimum-test failed: \(error)")
        exit(1)
    }
}

/// Every key the SMC has for the fans, with its type, size and current value.
///
/// Read-only. `F0Tg` and `F0Md` are the two this daemon writes, and on a chip that
/// discards those writes the question is what else is there - so this lists all of
/// them rather than the ones we already know about.
if CommandLine.arguments.contains("--dump-fan-keys") {
    do {
        let smc = try SMCDevice()
        print("key   type  size  value")
        for key in smc.allKeys().filter({ $0.hasPrefix("F") }).sorted() {
            guard let raw = smc.readRaw(key) else { print("\(key)  (unreadable)"); continue }
            let decoded = SMCValue.decode(type: raw.type, bytes: raw.bytes)
                .map { String(format: "%.2f", $0) } ?? "—"
            let hex = raw.bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
            print("\(key)  \(raw.type)  \(raw.bytes.count)     \(decoded)   [\(hex)]")
        }
        exit(0)
    } catch {
        print("dump failed: \(error)")
        exit(1)
    }
}

if CommandLine.arguments.contains("--probe") {
    do {
        let smc = try SMCDevice()
        let hardware = FanHardware(smc: smc)
        print("fans: \(hardware.fans.count)")
        for fan in hardware.fans {
            // The raw mode key, not `isOwned`: ownership is this process's own record
            // of what it took, and a probe has taken nothing, so it always said "no"
            // however hard the daemon beside it was holding the fan. What the SMC has
            // in F<n>Md is the thing worth seeing from outside.
            print(String(format: "  fan %d: %.0f rpm, target %.0f (limits %.0f-%.0f, F%dMd=%.0f)",
                         fan.index,
                         hardware.actualRPM(fan.index) ?? 0,
                         hardware.targetRPM(fan.index) ?? 0,
                         fan.limits.minRPM, fan.limits.maxRPM,
                         fan.index, hardware.rawMode(fan.index) ?? -1))
        }
        let temperatures = smc.temperatureReadings().map { ($0.key, $0.value) }
        SensorCatalog.configure(temperatures.map { SensorReading(key: $0.0, value: $0.1) })
        print("temperature sensors: \(temperatures.count)")
        for (zone, key, target) in smc.zoneTargets() {
            print(String(format: "  SMC steers %@ (%@) at %.1f C", SensorCatalog.smcZoneName(zone), key, target))
        }
        for (key, value) in temperatures.sorted(by: { $0.1 > $1.1 }).prefix(10) {
            let info = SensorCatalog.info(for: key)
            let name = info.name.padding(toLength: min(24, max(info.name.count, 24)), withPad: " ", startingAt: 0)
            print(String(format: "  %@ %@ %6.1f C", key, name, value))
        }
        exit(0)
    } catch {
        print("probe failed: \(error)")
        exit(1)
    }
}

// Verifies on real hardware that a forced target actually moves a fan. Needs root.
if CommandLine.arguments.contains("--selftest") {
    guard getuid() == 0 else {
        print("--selftest needs root: sudo fanctld --selftest")
        exit(1)
    }
    do {
        let smc = try SMCDevice()
        let hardware = FanHardware(smc: smc)
        guard let fan = hardware.fans.first else { print("no fans found"); exit(1) }

        let baseline = hardware.actualRPM(fan.index) ?? 0
        // Idle Apple Silicon fans sit at 0 rpm, well under the SMC's own minimum, so
        // aim clear of that floor rather than at baseline + a nudge.
        let target = min(max(baseline + 800, fan.limits.minRPM + 500), fan.limits.maxRPM)
        print(String(format: "fan %d at %.0f rpm, asking for %.0f rpm", fan.index, baseline, target))

        try hardware.setTarget(fan.index, rpm: target)
        print("forced mode engaged, raw mode key = \(hardware.rawMode(fan.index) ?? -1)")

        var peak = baseline
        for second in 1...8 {
            Thread.sleep(forTimeInterval: 1)
            let now = hardware.actualRPM(fan.index) ?? 0
            peak = max(peak, now)
            print(String(format: "  t+%ds  %.0f rpm", second, now))
        }

        try hardware.release(fan.index)
        let releasedOK = !hardware.isOwned(fan.index)
        print("released back to system: \(releasedOK)")

        let moved = peak - baseline
        if moved > 200 {
            print(String(format: "PASS: fan responded, rose %.0f rpm", moved))
            exit(0)
        } else {
            print(String(format: "FAIL: fan only moved %.0f rpm - writes are accepted but ignored", moved))
            exit(2)
        }
    } catch {
        print("selftest failed: \(error)")
        exit(1)
    }
}

// Development mode: run unprivileged against a socket of your choosing. Sensors are
// real, fan writes will be refused - useful for working on the UI.
let developmentMode = CommandLine.arguments.contains("--dev")

if !developmentMode && getuid() != 0 {
    FileHandle.standardError.write(Data(
        "fanctld must run as root (use --probe for a read-only check, or --dev for UI work)\n".utf8))
    exit(1)
}

if developmentMode && getuid() != 0 {
    Log.warn("development mode: not root, every fan write will be refused")
}

do {
    let daemon = try Daemon()
    try daemon.run()
} catch {
    Log.error("startup failed: \(error)")
    exit(1)
}
