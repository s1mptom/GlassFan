import Foundation
import Observation
import AppKit
import CryptoKit
import FanKit

/// Installs and removes the privileged daemon from inside the app.
///
/// Uses the system authorisation dialog rather than a terminal: dragging an app to
/// Applications and being asked for a password is what people expect, and it needs no
/// developer certificate. The script it runs ships inside the bundle, read-only.
@MainActor
@Observable
final class DaemonInstaller {
    enum Status: Equatable {
        case notInstalled
        case installed
        /// Installed, but not the build this app carries. The daemon is where the
        /// fan logic runs, so an app updated without its daemon quietly keeps the
        /// old rules - a curve that goes to zero, say, with a daemon that still
        /// floors it at the SMC minimum.
        case outdated
        case working(Job)
        case failed(String)
    }

    /// What a `working` installer is doing, so the window can say so.
    enum Job: Equatable { case install, update, reinstall, remove }

    private(set) var status: Status = .notInstalled

    /// Looked up straight away rather than on the window's first task: until then
    /// the status says "not installed", and a window that draws before that task
    /// runs would offer an Install button for a daemon that is right there.
    init() {
        refresh()
    }

#if DEBUG
    /// A fixed status for previews, whatever this Mac has installed.
    init(previewing status: Status) {
        self.status = status
    }
#endif

    static let daemonPath = "/usr/local/libexec/glassfan/fanctld"
    static let plistPath = "/Library/LaunchDaemons/com.glassfan.fanctld.plist"

    func refresh() {
        if case .working = status { return }
        guard FileManager.default.isExecutableFile(atPath: Self.daemonPath),
              FileManager.default.fileExists(atPath: Self.plistPath)
        else {
            // The daemon from the app's MacFans days: installed, running, and not
            // ours any more. Update replaces it and carries its config over.
            let macFansEra = FileManager.default.fileExists(
                atPath: "/Library/LaunchDaemons/com.macfans.fanctld.plist")
            status = macFansEra ? .outdated : .notInstalled
            return
        }
        status = Self.installedMatchesBundle() ? .installed : .outdated
    }

    /// Byte-for-byte: the daemon in the bundle against the one on disk.
    private static func installedMatchesBundle() -> Bool {
        guard let bundled = Bundle.main.url(forResource: "fanctld", withExtension: nil),
              let ours = try? Data(contentsOf: bundled),
              let theirs = try? Data(contentsOf: URL(fileURLWithPath: daemonPath))
        else { return true }   // nothing to compare against: do not nag
        return SHA256.hash(data: ours) == SHA256.hash(data: theirs)
    }

    func install() {
        let job: Job
        switch status {
        case .outdated: job = .update
        case .installed: job = .reinstall
        default: job = .install
        }
        run(script: "install-daemon.sh", job: job, expecting: .installed)
    }

    func uninstall() {
        run(script: "uninstall-daemon.sh", job: .remove, expecting: .notInstalled)
    }

    private func run(script name: String, job: Job, expecting success: Status) {
        guard let url = Bundle.main.url(forResource: name, withExtension: nil) else {
            status = .failed(L10n.t("В приложении нет \(name)", "\(name) is missing from the app"))
            return
        }
        status = .working(job)

        Task { @MainActor in
            // The script holds the main thread from the password dialog until the
            // new daemon is in place. Started straight away, it ran before the
            // window had drawn "working", and the button just pressed stayed on
            // screen the whole time; a moment's pause lets that frame through.
            try? await Task.sleep(for: .milliseconds(100))
            // AppleScript's `quoted form of` shell-quotes the path, so a bundle living
            // somewhere with spaces still works.
            let source = """
            do shell script "/bin/bash " & quoted form of "\(url.path)" with administrator privileges
            """
            var errorInfo: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)

            if let errorInfo {
                let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
                // -128 is the user cancelling the password dialog, which is not a failure.
                if code == -128 {
                    self.refresh()
                } else {
                    let message = errorInfo[NSAppleScript.errorMessage] as? String
                        ?? L10n.t("Не удалось выполнить установку", "The install could not be run")
                    self.status = .failed(message)
                }
                return
            }

            _ = result
            self.status = success
            self.refresh()
        }
    }
}
