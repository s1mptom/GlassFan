import Foundation
import FanKit

// A probe mode that needs no root, so the hardware can be inspected before installing.
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
