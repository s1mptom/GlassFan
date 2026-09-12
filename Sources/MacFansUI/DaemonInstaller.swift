import Foundation
import Observation
import AppKit
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
        case working
        case failed(String)
    }

    private(set) var status: Status = .notInstalled

    static let daemonPath = "/usr/local/libexec/macfans/fanctld"
    static let plistPath = "/Library/LaunchDaemons/com.macfans.fanctld.plist"

    func refresh() {
        if case .working = status { return }
        status = FileManager.default.isExecutableFile(atPath: Self.daemonPath)
            && FileManager.default.fileExists(atPath: Self.plistPath)
            ? .installed : .notInstalled
    }

    func install() {
        run(script: "install-daemon.sh", expecting: .installed)
    }

    func uninstall() {
        run(script: "uninstall-daemon.sh", expecting: .notInstalled)
    }

    private func run(script name: String, expecting success: Status) {
        guard let url = Bundle.main.url(forResource: name, withExtension: nil) else {
            status = .failed(L10n.t("В приложении нет \(name)", "\(name) is missing from the app"))
            return
        }
        status = .working

        Task { @MainActor in
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
