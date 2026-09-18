import Foundation
import FanKit

/// Owns the control loop: read sensors, decide, write fans, publish.
final class Daemon {
    static let version = "0.1.11"
    /// Overridable so the daemon can be run from a build directory during development,
    /// where /var/run is not writable and fan writes are expected to fail.
    static var socketPath = ProcessInfo.processInfo.environment["GLASSFAN_SOCKET"]
        ?? "/var/run/glassfan.sock"
    static var configPath = ProcessInfo.processInfo.environment["GLASSFAN_CONFIG"]
        ?? "/Library/Application Support/GlassFan/config.json"

    private let smc: SMCDevice
    private let hardware: FanHardware
    private let server: SocketServer
    private static let historyCapacity = 1800 // 30 min at 1 Hz
    private let history = History(capacity: Daemon.historyCapacity)
    private let loopQueue = DispatchQueue(label: "glassfan.control")
    private var timer: DispatchSourceTimer?
    private var watchdog: DispatchSourceTimer?

    private var config: AppConfig
    private var controllers: [Int: FanController] = [:]
    private var temperatureKeys: [String] = []
    /// The SMC's own fan setpoints, one per control zone. Read like a sensor but
    /// reported apart from them - see `SMCZoneTarget`.
    private var zoneTargetKeys: [(zone: Int, key: String)] = []
    /// Per-engine power, and what it says about which sensor is what. Absent when
    /// IOReport cannot be reached, which costs the machine only its learned names.
    private let power = PowerReport()
    private var affinity = EngineAffinity()
    /// Verdicts already published. A name that has appeared in the interface is not
    /// taken back: more evidence refines the sensors still unattributed, it does not
    /// rename the ones the user has been reading for a week.
    private var sensorEngines: [String: Engine] = [:]
    /// Set when the user quit GlassFan on purpose: the settings are kept but not
    /// applied, and the fans are the system's until the app opens again. Never
    /// restored from disk - a daemon that starts up has no reason to think anybody
    /// said goodbye to it, and starting suspended would silently disable a curve
    /// after a reboot.
    private var suspended = false
    /// Whether this daemon is the one that writes to the fans. A second daemon on the
    /// same machine reads, serves and records, and keeps its hands off the hardware.
    private let ownership = FanOwnership()
    private var ownsTheFans = true
    private var lastAffinityCheck = Date.distantPast
    private var lastSnapshot: Snapshot?
    private var lastTick = Date()
    /// The same moment on a clock that stops while the Mac sleeps - how the
    /// watchdog tells a sleep from a hang.
    private var lastTickAwake = Daemon.awakeSeconds()
    private var historySaver: DispatchSourceTimer?
    /// Last write failure per fan, so a persistent refusal is logged once per change
    /// rather than on every tick.
    private var lastWriteError: [Int: String?] = [:]
    private let stateLock = NSLock()

    init() throws {
        smc = try SMCDevice()
        hardware = FanHardware(smc: smc)
        server = SocketServer(path: Self.socketPath)
        config = Self.loadConfig(fanCount: hardware.fans.count)
        restoreHistory()
        discoverTemperatureSensors()
        // A charted list none of whose sensors exist here - a fresh install on a
        // chip that names its sensors differently, or a config carried over from
        // another Mac - gets this machine's own. A list with anything real in it is
        // the user's choice and is left alone.
        if SensorCatalog.isRetiredDefault(config.trackedSensors) {
            // Never edited, so nobody chose it - and three of its ten were mislabelled:
            // a core's probe, a battery-temperature alias billed as the GPU, and
            // chassis walls read as "palm rest".
            config.trackedSensors = SensorCatalog.trackedDefaults(available: temperatureKeys)
            Log.info("charted sensors moved to the current defaults: \(config.trackedSensors.joined(separator: ", "))")
            saveConfig()
        } else if Set(config.trackedSensors).isDisjoint(with: temperatureKeys) {
            config.trackedSensors = SensorCatalog.trackedDefaults(available: temperatureKeys)
            Log.info("charted sensors chosen for this hardware: \(config.trackedSensors.joined(separator: ", "))")
            saveConfig()
        }
        rebuildControllers()
    }

    // MARK: Startup

    func run() throws {
        Log.info("fanctld \(Self.version) starting, \(hardware.fans.count) fan(s), \(temperatureKeys.count) temperature sensors")
        if !zoneTargetKeys.isEmpty {
            Log.info("  SMC fan setpoints: \(zoneTargetKeys.map(\.key).joined(separator: ", "))")
        }
        for fan in hardware.fans {
            Log.info("  fan \(fan.index): \(Int(fan.limits.minRPM))-\(Int(fan.limits.maxRPM)) rpm")
        }

        // One writer. A second daemon fighting the first over the same keys makes the
        // fans hunt - spin up, stop, spin up - and neither can tell the other's writes
        // from the SMC keeping its own value.
        ownsTheFans = ownership.claim()
        guard ownsTheFans else {
            Log.warn("another fanctld already has the fans (lock at \(FanOwnership.path))")
            Log.warn("this one will read sensors and serve the interface, and write nothing")
            server.onCommand = { [weak self] command in self?.handle(command) }
            server.onConnect = { [weak self] fd in self?.greet(fd) }
            try server.start()
            installSignalHandling()
            startHistorySaver()
            let readOnly = DispatchSource.makeTimerSource(queue: loopQueue)
            readOnly.schedule(deadline: .now(), repeating: config.pollInterval)
            readOnly.setEventHandler { [weak self] in self?.tick() }
            readOnly.resume()
            self.timer = readOnly
            dispatchMain()
        }

        // Whatever the previous run - or another fan utility - left behind, start from
        // a known state.
        let leftovers = hardware.clearForeignForcedState()
        for (index, mode) in leftovers.sorted(by: { $0.key < $1.key }) {
            Log.warn("fan \(index) was left in forced mode (F\(index)Md = \(Int(mode))) by another process - reset to auto")
        }

        server.onCommand = { [weak self] command in self?.handle(command) }
        server.onConnect = { [weak self] fd in self?.greet(fd) }
        try server.start()

        installSignalHandling()
        startWatchdog()
        startHistorySaver()

        let timer = DispatchSource.makeTimerSource(queue: loopQueue)
        timer.schedule(deadline: .now(), repeating: config.pollInterval)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer

        dispatchMain()
    }

    private func discoverTemperatureSensors() {
        let readings = smc.temperatureReadings()
        temperatureKeys = readings.map(\.key).sorted()
        zoneTargetKeys = smc.zoneTargets().map { (zone: $0.zone, key: $0.key) }
        sensorEngines = Self.loadEngines()
        // Names for the parts no table covers are read off this machine's own
        // layout, so the catalogue has to be told what this machine reports.
        SensorCatalog.configure(readings.map { SensorReading(key: $0.key, value: $0.value) },
                                engines: sensorEngines)
    }

    /// Folds this tick into what is known about which sensor answers to which engine,
    /// and publishes any sensor that has become clear since the last check.
    ///
    /// Checked every few minutes rather than every tick: solving for two hundred
    /// sensors is cheap but not free, and nothing about the answer changes in a
    /// second.
    private func learnEngines(temperatures: [String: Double], interval: TimeInterval) {
        guard let power else { return }
        affinity.observe(power: power.sinceLastReading(), temperatures: temperatures,
                         interval: interval)
        guard Date().timeIntervalSince(lastAffinityCheck) >= 300 else { return }
        lastAffinityCheck = Date()

        var learned = false
        for (key, verdict) in affinity.verdicts() where sensorEngines[key] == nil {
            sensorEngines[key] = verdict.engine
            learned = true
            Log.info(String(format: "%@ follows the %@ (%.0f%% of what moves it, fit %.2f)",
                            key, verdict.engine.rawValue, verdict.share * 100, verdict.fit))
        }
        guard learned else { return }
        Self.saveEngines(sensorEngines)
        SensorCatalog.configure(temperatures.map { SensorReading(key: $0.key, value: $0.value) },
                                engines: sensorEngines)
    }

    // MARK: Learned engines, kept across restarts

    static var enginesPath: String {
        (configPath as NSString).deletingLastPathComponent + "/engines.json"
    }

    /// Tied to the machine, because the answer is: a config copied to another Mac
    /// would carry names measured on this one's silicon.
    private static var machineIdentity: String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return "unknown" }
        return String(cString: bytes)
    }

    private struct LearnedEngines: Codable {
        var machine: String
        var engines: [String: Engine]
    }

    private static func loadEngines() -> [String: Engine] {
        guard let data = FileManager.default.contents(atPath: enginesPath),
              let saved = try? JSONDecoder().decode(LearnedEngines.self, from: data),
              saved.machine == machineIdentity
        else { return [:] }
        Log.info("sensor engines restored: \(saved.engines.count) of them")
        return saved.engines
    }

    private static func saveEngines(_ engines: [String: Engine]) {
        let directory = (enginesPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(
            LearnedEngines(machine: machineIdentity, engines: engines)) else { return }
        try? data.write(to: URL(fileURLWithPath: enginesPath), options: .atomic)
    }

    private func rebuildControllers() {
        var rebuilt: [Int: FanController] = [:]
        for fan in hardware.fans {
            let settings = config.fans.first { $0.id == fan.index }
                ?? FanSettings(id: fan.index, mode: .auto, fixedRPM: fan.limits.minRPM,
                               sensorKeys: [], curve: FanCurve(points: []),
                               hysteresis: 2, smoothing: 0.3)
            if var existing = controllers[fan.index] {
                existing.settings = settings
                existing.limits = fan.limits
                rebuilt[fan.index] = existing
            } else {
                rebuilt[fan.index] = FanController(settings: settings, limits: fan.limits)
            }
        }
        controllers = rebuilt
    }

    // MARK: Control loop

    private func tick() {
        stateLock.lock()
        let sinceLastTick = Date().timeIntervalSince(lastTick)
        lastTick = Date()
        lastTickAwake = Self.awakeSeconds()
        stateLock.unlock()

        var temperatures: [String: Double] = [:]
        temperatures.reserveCapacity(temperatureKeys.count)
        for key in temperatureKeys {
            if let reading = smc.read(key) { temperatures[key] = reading.value }
        }

        // A tick that came after a sleep spans hours of wall clock and no work at
        // all; folding it in would tell the learner that an idle engine heated the
        // whole machine. Only ticks that look like ticks are learned from.
        if sinceLastTick > 0, sinceLastTick < config.pollInterval * 3 {
            learnEngines(temperatures: temperatures, interval: sinceLastTick)
        }

        var readings: [FanReading] = []
        for fan in hardware.fans {
            guard var controller = controllers[fan.index] else { continue }
            let decided = controller.update(temperatures: temperatures, emergencyTemp: config.emergencyTemp)
            controllers[fan.index] = controller
            // Suspended is not a mode, so the controller still runs and the chart
            // still has a driving temperature to show when the app comes back. It is
            // only the writing that stops.
            // Suspended is a choice the user made; not owning the fans is a fact about
            // the machine. Either way this tick writes nothing.
            let target = (suspended || !ownsTheFans) ? nil : decided

            // Whether we are actually in control is decided by the write, not by the
            // intention behind it.
            var applied = false
            var writeError: String?
            var writeFailure: FanWriteFailure?
            var acquiring = false
            do {
                if let target {
                    try hardware.setTarget(fan.index, rpm: target)
                    applied = true
                } else if ownsTheFans {
                    try hardware.release(fan.index)
                }
            } catch {
                writeError = "\(error)"
                // Still taking the fan is not the same as not being able to. On M3 and
                // later the thermal manager takes seconds to let go, and every second
                // of that arrives here as a refusal.
                if hardware.isAcquiring {
                    acquiring = true
                    if lastWriteError[fan.index] != writeError {
                        Log.info("fan \(fan.index): waiting for the thermal manager to let go")
                    }
                } else {
                    writeFailure = (error as? SMCDevice.Failure).map {
                        if case .ignored = $0 { return .ignored } else { return .refused }
                    } ?? .refused
                    if lastWriteError[fan.index] != writeError {
                        Log.error("fan \(fan.index): \(error)")
                    }
                }
            }
            lastWriteError[fan.index] = writeError

            readings.append(FanReading(
                index: fan.index,
                actualRPM: hardware.actualRPM(fan.index) ?? 0,
                // What the SMC actually holds, not what we asked for: with the write
                // discarded those are different numbers, and the honest one is the
                // machine's.
                targetRPM: hardware.targetRPM(fan.index) ?? target ?? 0,
                limits: fan.limits,
                mode: controller.settings.mode,
                forced: applied,
                drivingTemp: controller.lastDrivingTemp,
                emergency: controller.isEmergency,
                writeError: writeError,
                writeFailure: writeFailure,
                acquiring: acquiring
            ))
        }

        let targets = zoneTargetKeys.compactMap { zone, key in
            smc.read(key).map { SMCZoneTarget(zone: zone, target: $0.value) }
        }

        let now = Date().timeIntervalSince1970
        let snapshot = Snapshot(
            time: now,
            sensors: temperatures.map { SensorReading(key: $0.key, value: $0.value) }
                .sorted { $0.key < $1.key },
            fans: readings,
            config: config,
            daemonVersion: Self.version,
            smcZoneTargets: targets.isEmpty ? nil : targets,
            sensorEngines: sensorEngines.isEmpty ? nil : sensorEngines
        )
        lastSnapshot = snapshot

        let tracked = Set(config.trackedSensors).union(config.fans.flatMap(\.sensorKeys))
        history.append(HistorySample(
            t: now,
            temps: temperatures.filter { tracked.contains($0.key) },
            fanRPM: readings.map(\.actualRPM)
        ))

        server.broadcast(.snapshot(snapshot))
    }

    // MARK: Clients

    private func greet(_ fd: Int32) {
        loopQueue.async { [weak self] in
            guard let self else { return }
            self.server.send(.history(self.history.all()), to: fd)
            if let snapshot = self.lastSnapshot {
                self.server.send(.snapshot(snapshot), to: fd)
            }
        }
    }

    private func handle(_ command: ClientCommand) {
        loopQueue.async { [weak self] in
            guard let self else { return }
            switch command {
            case .hello:
                // Someone has the app open again, so the settings apply again.
                if self.suspended {
                    self.suspended = false
                    Log.info("client back - applying the fan settings again")
                }

            case .setConfig(let newConfig):
                let intervalChanged = newConfig.pollInterval != self.config.pollInterval
                self.config = newConfig
                self.rebuildControllers()
                self.saveConfig()
                if intervalChanged {
                    self.timer?.schedule(deadline: .now(), repeating: newConfig.pollInterval)
                }
                Log.info("config updated: " + newConfig.fans
                    .map { "fan\($0.id)=\($0.mode.rawValue)" }.joined(separator: " "))

            case .goodbye:
                // Deliberate, so the fans go back to the system - but the settings
                // stay exactly as they are, ready for the next launch.
                Log.info("GlassFan was quit - fans back to the system until it opens again")
                self.suspended = true
                self.hardware.releaseAll()
                for index in self.controllers.keys { self.controllers[index]?.reset() }

            case .releaseAll:
                Log.warn("release requested by client")
                for index in self.controllers.keys {
                    self.controllers[index]?.settings.mode = .auto
                    self.controllers[index]?.reset()
                }
                for index in self.config.fans.indices { self.config.fans[index].mode = .auto }
                self.hardware.releaseAll()
                self.saveConfig()
            }
        }
    }

    // MARK: Safety

    /// If the control loop stops ticking, the fans must not stay pinned where we left them.
    private func startWatchdog() {
        let watchdog = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "glassfan.watchdog"))
        watchdog.schedule(deadline: .now() + 5, repeating: 5)
        watchdog.setEventHandler { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            let wallAge = Date().timeIntervalSince(self.lastTick)
            let awakeAge = Self.awakeSeconds() - self.lastTickAwake
            self.stateLock.unlock()
            let limit = max(10, self.config.pollInterval * 10)
            switch LoopHealth.classify(wallAge: wallAge, awakeAge: awakeAge, limit: limit) {
            case .ticking:
                break
            case .slept(let seconds):
                // Not a fault. The fans are still handed back: while the Mac slept
                // the system had them, and the next tick takes control afresh
                // rather than trusting ownership from before the sleep.
                Log.info("woke after \(Int(seconds))s asleep - fans back to the system until the next reading")
                self.hardware.releaseAll()
                self.stateLock.lock()
                self.lastTick = Date()
                self.lastTickAwake = Self.awakeSeconds()
                self.stateLock.unlock()
            case .stalled(let seconds):
                Log.error("control loop stalled for \(Int(seconds))s - releasing fans to the system")
                self.hardware.releaseAll()
            }
        }
        watchdog.resume()
        self.watchdog = watchdog
    }

    private func installSignalHandling() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                Log.info("signal \(sig): releasing fans and exiting")
                self?.hardware.releaseAll()
                // An update or a restart arrives here; the chart survives it.
                self?.saveHistory()
                self?.server.stop()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
        signal(SIGPIPE, SIG_IGN)
    }

    private var signalSources: [DispatchSourceSignal] = []

    // MARK: History persistence

    static var historyPath: String {
        ProcessInfo.processInfo.environment["GLASSFAN_HISTORY"]
            ?? (configPath as NSString).deletingLastPathComponent + "/history.json"
    }

    /// Seconds on a clock that does not run while the Mac is asleep.
    static func awakeSeconds() -> TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1_000_000_000
    }

    private func restoreHistory() {
        guard let data = FileManager.default.contents(atPath: Self.historyPath),
              let saved = try? JSONDecoder().decode([HistorySample].self, from: data)
        else { return }
        let kept = HistoryRecord.restorable(saved, now: Date().timeIntervalSince1970,
                                            capacity: Self.historyCapacity)
        history.restore(kept)
        Log.info("history restored: \(kept.count) of \(saved.count) samples still in range")
    }

    /// On exit, and every five minutes as a net for the exits that give no
    /// warning - a crash, a power cut. Five, not one: a half hour of history is a
    /// few hundred kilobytes, and rewriting it every minute is a gigabyte of SSD
    /// writes a day for a chart. Nothing is written when nothing was recorded, so
    /// a sleeping Mac writes nothing.
    private func startHistorySaver() {
        let saver = DispatchSource.makeTimerSource(queue: loopQueue)
        saver.schedule(deadline: .now() + 300, repeating: 300)
        saver.setEventHandler { [weak self] in self?.saveHistory() }
        saver.resume()
        historySaver = saver
    }

    private func saveHistory() {
        guard let samples = history.unsaved() else { return }
        let directory = (Self.historyPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(HistoryRecord.compacted(samples)) else { return }
        do {
            try data.write(to: URL(fileURLWithPath: Self.historyPath), options: .atomic)
            history.markSaved()
        } catch {
            Log.warn("history not saved: \(error)")
        }
    }

    // MARK: Config persistence

    private static func loadConfig(fanCount: Int) -> AppConfig {
        // A config left where MacFans kept it counts, until the installer moves it.
        let legacy = "/Library/Application Support/MacFans/config.json"
        let path = FileManager.default.fileExists(atPath: configPath) ? configPath : legacy
        guard let data = FileManager.default.contents(atPath: path),
              let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            Log.info("no saved config, starting in auto")
            return .default(fanCount: fanCount)
        }
        var config = decoded
        // A config written for different hardware must not leave a fan unmanaged.
        for index in 0..<fanCount where !config.fans.contains(where: { $0.id == index }) {
            config.fans.append(FanSettings(id: index, mode: .auto, fixedRPM: 2000,
                                           sensorKeys: [], curve: FanCurve(points: []),
                                           hysteresis: 2, smoothing: 0.3))
        }
        config.fans = config.fans.filter { $0.id < fanCount }.sorted { $0.id < $1.id }
        return config
    }

    private func saveConfig() {
        let directory = (Self.configPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: URL(fileURLWithPath: Self.configPath), options: .atomic)
    }
}
