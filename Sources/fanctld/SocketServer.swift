import Foundation
import FanKit

/// Unix-socket server speaking newline-delimited JSON.
///
/// Deliberately boring: one accept thread, one reader thread per client. A client that
/// stalls or dies can only lose itself, never the control loop.
final class SocketServer {
    private let path: String
    private var listenFD: Int32 = -1
    private let lock = NSLock()
    private var clients: [Int32] = []
    private let acceptQueue = DispatchQueue(label: "glassfan.accept")
    private let clientQueue = DispatchQueue(label: "glassfan.client", attributes: .concurrent)

    var onCommand: ((ClientCommand) -> Void)?
    var onConnect: ((Int32) -> Void)?

    init(path: String) {
        self.path = path
    }

    func start() throws {
        unlink(path)
        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else { throw POSIXError(.EADDRNOTAVAIL) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            throw POSIXError(.ENAMETOOLONG)
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: pathBytes)
        }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listenFD, $0, size) }
        }
        guard bound == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard listen(listenFD, 8) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }

        // Root owns it; the logged-in user's group may talk to it.
        chmod(path, 0o660)
        if getuid() == 0 {
            chown(path, 0, 20) // gid 20 = staff
        }

        acceptQueue.async { [weak self] in self?.acceptLoop() }
        Log.info("listening on \(path)")
    }

    private func acceptLoop() {
        while true {
            let fd = accept(listenFD, nil, nil)
            if fd < 0 {
                if errno == EINTR { continue }
                Log.warn("accept failed: \(String(cString: strerror(errno)))")
                return
            }
            var on: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            lock.lock(); clients.append(fd); lock.unlock()
            onConnect?(fd)
            clientQueue.async { [weak self] in self?.readLoop(fd) }
        }
    }

    private func readLoop(_ fd: Int32) {
        var buffer = NDJSONDecoderBuffer(maxMessageBytes: 4 * 1024 * 1024)
        var chunk = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let n = recv(fd, &chunk, chunk.count, 0)
            if n <= 0 {
                if n < 0 && errno == EINTR { continue }
                break
            }
            do {
                let commands = try buffer.append(Data(chunk.prefix(n)), as: ClientCommand.self)
                for command in commands { onCommand?(command) }
            } catch {
                Log.warn("client \(fd) flooded the socket, dropping it")
                break
            }
        }
        drop(fd)
    }

    private func drop(_ fd: Int32) {
        lock.lock()
        clients.removeAll { $0 == fd }
        lock.unlock()
        close(fd)
    }

    func send(_ message: DaemonMessage, to fd: Int32) {
        guard let data = try? NDJSONEncoder.encode(message) else { return }
        transmit(data, to: fd)
    }

    func broadcast(_ message: DaemonMessage) {
        guard let data = try? NDJSONEncoder.encode(message) else { return }
        lock.lock()
        let targets = clients
        lock.unlock()
        for fd in targets { transmit(data, to: fd) }
    }

    private func transmit(_ data: Data, to fd: Int32) {
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let sent = Darwin.send(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset, 0)
                if sent <= 0 {
                    if errno == EINTR { continue }
                    drop(fd)
                    return
                }
                offset += sent
            }
        }
    }

    func stop() {
        lock.lock()
        let targets = clients
        clients.removeAll()
        lock.unlock()
        for fd in targets { close(fd) }
        if listenFD >= 0 { close(listenFD) }
        unlink(path)
    }
}
