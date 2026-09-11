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
    static let socketPath = ProcessInfo.processInfo.environment["MACFANS_SOCKET"]
        ?? "/var/run/macfans.sock"

    private(set) var snapshot: Snapshot?
    private(set) var history: [HistorySample] = []
    private(set) var isConnected = false
    private(set) var lastError: String?

    private var fd: Int32 = -1
    private var readerThread: Thread?
    private let historyLimit = 1800

    /// Config being edited in the UI. Kept apart from the daemon's copy so typing in a
    /// field is not fought by every incoming snapshot.
    var draftConfig: AppConfig?

    var config: AppConfig? { draftConfig ?? snapshot?.config }

    func start() {
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
        thread.name = "macfans.reader"
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
            history = samples

        case .snapshot(let snapshot):
            self.snapshot = snapshot
            let tracked = Set(snapshot.config.trackedSensors)
                .union(snapshot.config.fans.flatMap(\.sensorKeys))
            var temps: [String: Double] = [:]
            for sensor in snapshot.sensors where tracked.contains(sensor.key) {
                temps[sensor.key] = sensor.value
            }
            history.append(HistorySample(t: snapshot.time, temps: temps,
                                         fanRPM: snapshot.fans.map(\.actualRPM)))
            if history.count > historyLimit {
                history.removeFirst(history.count - historyLimit)
            }
            // Adopt the daemon's config once, so the UI starts from the real state.
            if draftConfig == nil { draftConfig = snapshot.config }

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

    /// Pushes the edited config to the daemon.
    func commit() {
        guard let config = draftConfig else { return }
        send(.setConfig(config))
    }

    func releaseAll() {
        send(.releaseAll)
        draftConfig = nil
    }

    // MARK: Convenience for views

    func reading(for key: String) -> Double? {
        snapshot?.sensors.first { $0.key == key }?.value
    }

    var hottest: SensorReading? {
        snapshot?.sensors.max { $0.value < $1.value }
    }

    func sensors(in group: SensorGroup) -> [SensorReading] {
        (snapshot?.sensors ?? []).filter { SensorCatalog.info(for: $0.key).group == group }
    }
}
