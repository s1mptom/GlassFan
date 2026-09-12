import Foundation
import FanKit

/// Owns the control loop: read sensors, decide, write fans, publish.
final class Daemon {
    static let version = "0.1.0"
    /// Overridable so the daemon can be run from a build directory during development,
    /// where /var/run is not writable and fan writes are expected to fail.
    static var socketPath = ProcessInfo.processInfo.environment["MACFANS_SOCKET"]
        ?? "/var/run/macfans.sock"
    static var configPath = ProcessInfo.processInfo.environment["MACFANS_CONFIG"]
        ?? "/Library/Application Support/MacFans/config.json"

    private let smc: SMCDevice
    private let hardware: FanHardware
    private let server: SocketServer
    private let history = History(capacity: 1800) // 30 min at 1 Hz
    private let loopQueue = DispatchQueue(label: "macfans.control")
    private var timer: DispatchSourceTimer?
    private var watchdog: DispatchSourceTimer?

    private var config: AppConfig
    private var controllers: [Int: FanController] = [:]
    private var temperatureKeys: [String] = []
    private var lastSnapshot: Snapshot?
    private var lastTick = Date()
    /// Last write failure per fan, so a persistent refusal is logged once per change
    /// rather than on every tick.
    private var lastWriteError: [Int: String?] = [:]
    private let stateLock = NSLock()

    init() throws {
        smc = try SMCDevice()
        hardware = FanHardware(smc: smc)
        server = SocketServer(path: Self.socketPath)
        config = Self.loadConfig(fanCount: hardware.fans.count)
        discoverTemperatureSensors()
        rebuildControllers()
    }

    // MARK: Startup

    func run() throws {
        Log.info("fanctld \(Self.version) starting, \(hardware.fans.count) fan(s), \(temperatureKeys.count) temperature sensors")
        for fan in hardware.fans {
            Log.info("  fan \(fan.index): \(Int(fan.limits.minRPM))-\(Int(fan.limits.maxRPM)) rpm")
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

        let timer = DispatchSource.makeTimerSource(queue: loopQueue)
        timer.schedule(deadline: .now(), repeating: config.pollInterval)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer

        dispatchMain()
    }

    private func discoverTemperatureSensors() {
        let candidates = smc.allKeys().filter { $0.hasPrefix("T") }
        temperatureKeys = candidates.filter { key in
            guard let reading = smc.read(key) else { return false }
            return SensorCatalog.looksLikeTemperature(key: key, type: reading.type, value: reading.value)
        }.sorted()
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
        lastTick = Date()
        stateLock.unlock()

        var temperatures: [String: Double] = [:]
        temperatures.reserveCapacity(temperatureKeys.count)
        for key in temperatureKeys {
            if let reading = smc.read(key) { temperatures[key] = reading.value }
        }

        var readings: [FanReading] = []
        for fan in hardware.fans {
            guard var controller = controllers[fan.index] else { continue }
            let target = controller.update(temperatures: temperatures, emergencyTemp: config.emergencyTemp)
            controllers[fan.index] = controller

            // Whether we are actually in control is decided by the write, not by the
            // intention behind it.
            var applied = false
            var writeError: String?
            do {
                if let target {
                    try hardware.setTarget(fan.index, rpm: target)
                    applied = true
                } else {
                    try hardware.release(fan.index)
                }
            } catch {
                writeError = "\(error)"
                if lastWriteError[fan.index] != writeError {
                    Log.error("fan \(fan.index): \(error)")
                }
            }
            lastWriteError[fan.index] = writeError

            readings.append(FanReading(
                index: fan.index,
                actualRPM: hardware.actualRPM(fan.index) ?? 0,
                targetRPM: target ?? hardware.targetRPM(fan.index) ?? 0,
                limits: fan.limits,
                mode: controller.settings.mode,
                forced: applied,
                drivingTemp: controller.lastDrivingTemp,
                emergency: controller.isEmergency,
                writeError: writeError
            ))
        }

        let now = Date().timeIntervalSince1970
        let snapshot = Snapshot(
            time: now,
            sensors: temperatures.map { SensorReading(key: $0.key, value: $0.value) }
                .sorted { $0.key < $1.key },
            fans: readings,
            config: config,
            daemonVersion: Self.version
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
                break

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
        let watchdog = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "macfans.watchdog"))
        watchdog.schedule(deadline: .now() + 5, repeating: 5)
        watchdog.setEventHandler { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            let age = Date().timeIntervalSince(self.lastTick)
            self.stateLock.unlock()
            let limit = max(10, self.config.pollInterval * 10)
            if age > limit {
                Log.error("control loop stalled for \(Int(age))s - releasing fans to the system")
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
                self?.server.stop()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
        signal(SIGPIPE, SIG_IGN)
    }

    private var signalSources: [DispatchSourceSignal] = []

    // MARK: Config persistence

    private static func loadConfig(fanCount: Int) -> AppConfig {
        guard let data = FileManager.default.contents(atPath: configPath),
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
