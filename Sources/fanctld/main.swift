import Foundation
import FanKit

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

if CommandLine.arguments.contains("--probe") {
    do {
        let smc = try SMCDevice()
        let hardware = FanHardware(smc: smc)
        print("fans: \(hardware.fans.count)")
        for fan in hardware.fans {
            print(String(format: "  fan %d: %.0f rpm (limits %.0f-%.0f, forced=%@)",
                         fan.index,
                         hardware.actualRPM(fan.index) ?? 0,
                         fan.limits.minRPM, fan.limits.maxRPM,
                         hardware.isOwned(fan.index) ? "yes" : "no"))
        }
        let temperatures = smc.allKeys().filter { $0.hasPrefix("T") }.compactMap { key -> (String, Double)? in
            guard let reading = smc.read(key),
                  SensorCatalog.looksLikeTemperature(key: key, type: reading.type, value: reading.value)
            else { return nil }
            return (key, reading.value)
        }
        print("temperature sensors: \(temperatures.count)")
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
