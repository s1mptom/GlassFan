import Foundation

/// One daemon writes to the fans, and the rest do not.
///
/// launchd keeps a single copy of the installed daemon running, which is why this was
/// never needed - until a second one was started from a build directory beside it.
/// Two daemons writing the same keys once a second is not a slow drift into confusion:
/// the fans visibly hunt, spinning up and stopping every few seconds as each writes
/// over the other, and whichever loses the last exchange can leave the test key raised
/// with the machine's own thermal management switched off.
///
/// Nothing detected it. Each daemon read the keys back and saw values it had not
/// written, which is exactly what it is built to notice - but "the SMC kept its own
/// value" and "the other one of me kept its value" look identical from inside.
///
/// So ownership is claimed explicitly, with a lock that the operating system releases
/// however the holder dies: a crash, a kill -9, a power cut. A daemon that cannot get
/// it still reads sensors, still serves the interface and still keeps history - it
/// simply does not write, and says so.
final class FanOwnership {
    private var descriptor: Int32 = -1

    /// Beside the socket rather than the config: it describes who is running now, not
    /// what was chosen, and it should not survive into a backup or a migration.
    static var path: String {
        ProcessInfo.processInfo.environment["GLASSFAN_LOCK"]
            ?? (Daemon.socketPath as NSString).deletingLastPathComponent + "/glassfan.fans.lock"
    }

    /// Takes the lock, or reports who has it.
    ///
    /// `flock` and not a pid file, because a pid file outlives the process that wrote
    /// it: after a crash the next daemon finds a pid that now belongs to something else
    /// entirely, and either refuses to run forever or ignores the file and learns
    /// nothing. The kernel drops an `flock` when the descriptor closes, which happens
    /// however the holder ends.
    @discardableResult
    func claim() -> Bool {
        let fd = open(Self.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else {
            // Nowhere to put the lock is not a reason to refuse to work; it is a reason
            // to say so. A machine with one daemon on it - which is every machine that
            // has not been developed on - behaves exactly as before.
            Log.warn("cannot open \(Self.path): running without an ownership lock")
            return true
        }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return false
        }
        descriptor = fd
        return true
    }

    deinit {
        if descriptor >= 0 { close(descriptor) }   // releases the lock
    }
}
