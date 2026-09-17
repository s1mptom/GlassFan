import Foundation
import Observation
import FanKit

/// Talks to fanctld over its unix socket and keeps the latest state for the UI.
///
/// Reconnects on its own: the daemon can be restarted, updated or stopped underneath
/// the app and the window simply goes quiet and comes back.
@MainActor
@Observable
final class DaemonClient {
    static let socketPath = ProcessInfo.processInfo.environment["GLASSFAN_SOCKET"]
        ?? "/var/run/glassfan.sock"

    /// The snapshot and the history it extends, as one value.
    ///
    /// They were two stored properties, and applying a reading wrote three
    /// times - the snapshot, then an append to the history, then the trim of
    /// its oldest sample - and every write was its own SwiftUI pass: the
    /// overview re-laid out its chart about 2.7 times per one-a-second
    /// reading, measured with `_printChanges`. One stored value, one write,
    /// one pass. The two names below are what everything else reads.
    private struct Feed {
        var snapshot: Snapshot?
        var history: [HistorySample] = []
    }
    private var feed = Feed()

    var snapshot: Snapshot? { feed.snapshot }
    var history: [HistorySample] { feed.history }
    private(set) var isConnected = false
    private(set) var lastError: String?

    private var fd: Int32 = -1
    private var readerThread: Thread?
    private let historyLimit = 1800

    /// Optimistic overlay while an edit is in flight. The daemon stays the source of
    /// truth: as soon as it confirms (or if it changes the config from elsewhere) the
    /// overlay is dropped, so the UI can never drift away from what is actually running.
    var draftConfig: AppConfig?
    /// The config last sent, awaiting confirmation.
    private var pendingConfig: AppConfig?
    private var pendingSince: Date?

    var config: AppConfig? { draftConfig ?? snapshot?.config }

    /// A client holding the fixture instead of a socket, so previews and screenshots
    /// render the same state every time without a daemon running.
    static func demo(connected: Bool = true, alarming: Bool = false, fanless: Bool = false,
                     sleptAt: Int? = nil) -> DaemonClient {
        let client = DaemonClient()
        guard connected else { return client }
        let snapshot = DemoFixture.snapshot(alarming: alarming, fanless: fanless)
        // The fixture is another Mac's sensor list, so the catalogue has to be told
        // about it just as a live snapshot would - otherwise a preview renders this
        // machine's layout over the fixture's keys.
        SensorCatalog.configure(snapshot.sensors, engines: snapshot.sensorEngines ?? [:])
        client.feed = Feed(snapshot: snapshot, history: DemoFixture.history(sleptAt: sleptAt))
        client.isConnected = true
        return client
    }

    func start() {
        if DemoFixture.isEnabled {
            let snapshot = DemoFixture.snapshot()
            SensorCatalog.configure(snapshot.sensors, engines: snapshot.sensorEngines ?? [:])
            feed = Feed(snapshot: snapshot, history: DemoFixture.history())
            isConnected = true
            return
        }
        connect()
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isConnected else { return }
                self.connect()
            }
        }
    }

    private func connect() {
        let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(Self.socketPath.utf8)
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: pathBytes) }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(socketFD, $0, size) }
        }
        guard result == 0 else {
            close(socketFD)
            lastError = L10n.t("Демон не отвечает", "Daemon is not responding")
            return
        }

        var on: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

        fd = socketFD
        isConnected = true
        lastError = nil
        send(.hello)

        let thread = Thread { [weak self] in self?.readLoop(socketFD) }
        thread.name = "glassfan.reader"
        thread.start()
        readerThread = thread
    }

    private nonisolated func readLoop(_ socketFD: Int32) {
        var buffer = NDJSONDecoderBuffer()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let n = recv(socketFD, &chunk, chunk.count, 0)
            if n <= 0 {
                if n < 0 && errno == EINTR { continue }
                break
            }
            guard let messages = try? buffer.append(Data(chunk.prefix(n)), as: DaemonMessage.self)
            else { continue }
            for message in messages {
                Task { @MainActor [weak self] in self?.apply(message) }
            }
        }
        close(socketFD)
        Task { @MainActor [weak self] in self?.handleDisconnect() }
    }

    private func handleDisconnect() {
        isConnected = false
        fd = -1
        lastError = L10n.t("Связь с демоном потеряна", "Lost contact with the daemon")
    }

    private func apply(_ message: DaemonMessage) {
        switch message {
        case .history(let samples):
            feed.history = samples

        case .snapshot(let snapshot):
            // The names of parts no table covers are read off the key layout, and
            // the app may well be looking at a Mac it has no table for. Ignored when
            // the list has not changed, so this costs nothing per reading.
            SensorCatalog.configure(snapshot.sensors, engines: snapshot.sensorEngines ?? [:])
            let tracked = Set(snapshot.config.trackedSensors)
                .union(snapshot.config.fans.flatMap(\.sensorKeys))
            var temps: [String: Double] = [:]
            for sensor in snapshot.sensors where tracked.contains(sensor.key) {
                temps[sensor.key] = sensor.value
            }
            // Built off to the side and written once: see `Feed`.
            var history = feed.history
            history.append(HistorySample(t: snapshot.time, temps: temps,
                                         fanRPM: snapshot.fans.map(\.actualRPM)))
            if history.count > historyLimit {
                history.removeFirst(history.count - historyLimit)
            }
            feed = Feed(snapshot: snapshot, history: history)
            reconcileConfig(with: snapshot.config)

        case .failure(let text):
            lastError = text
        }
    }

    func send(_ command: ClientCommand) {
        guard fd >= 0, let data = try? NDJSONEncoder.encode(command) else { return }
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let sent = Darwin.send(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset, 0)
                if sent <= 0 { break }
                offset += sent
            }
        }
    }

    /// Reconciles the optimistic overlay against what the daemon reports.
    private func reconcileConfig(with daemonConfig: AppConfig) {
        guard let pending = pendingConfig else {
            // Nothing in flight: the daemon's copy is the truth.
            draftConfig = nil
            return
        }
        if daemonConfig == pending {
            pendingConfig = nil
            pendingSince = nil
            draftConfig = nil
            return
        }
        // A change we never made, or a commit that went missing - either way the
        // daemon wins rather than the UI showing a state nothing is in.
        if let since = pendingSince, Date().timeIntervalSince(since) > 3 {
            pendingConfig = nil
            pendingSince = nil
            draftConfig = nil
        }
    }

    /// Pushes the edited config to the daemon.
    func commit() {
        guard let config = draftConfig else { return }
        pendingConfig = config
        pendingSince = Date()
        send(.setConfig(config))
    }

    /// Tells the daemon the user has quit, and waits for it to land.
    ///
    /// Blocking, briefly, because the process is about to go: `send` hands the bytes
    /// to the kernel, but an app that terminates in the same breath can have the
    /// socket torn down with the write still in flight, and then the fans stay pinned
    /// after a goodbye that looked like it was sent. A tenth of a second is not felt
    /// at quit and is far longer than a unix socket needs.
    func sayGoodbye() {
        guard fd >= 0 else { return }
        send(.goodbye)
        Thread.sleep(forTimeInterval: 0.1)
    }

    func releaseAll() {
        send(.releaseAll)
        draftConfig = nil
        pendingConfig = nil
        pendingSince = nil
    }

    // MARK: Convenience for views

    func reading(for key: String) -> Double? {
        snapshot?.sensors.first { $0.key == key }?.value
    }

    var hottest: SensorReading? {
        snapshot?.sensors.max { $0.value < $1.value }
    }
}
