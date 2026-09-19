import Testing
import Foundation
@testable import GlassFanUI

/// What the window says while there is no daemon to talk to.
@Suite("Daemon absence")
struct DaemonAbsenceTests {
    @Test("mid-update, the window says so rather than offering to install")
    func updating() {
        let absence = DaemonAbsence.of(.working(.update), quietFor: 1)
        #expect(absence == .working(.update))
        #expect(absence.isTransient)
        #expect(absence.title != DaemonAbsence.notInstalled.title)
    }

    @Test("installed but quiet is a restart for a while, then a daemon that is not answering")
    func quietInstalledDaemon() {
        for status in [DaemonInstaller.Status.installed, .outdated] {
            #expect(DaemonAbsence.of(status, quietFor: 0) == .connecting)
            #expect(DaemonAbsence.of(status, quietFor: DaemonAbsence.patience - 0.1) == .connecting)
            #expect(DaemonAbsence.of(status, quietFor: DaemonAbsence.patience) == .silent)
        }
        #expect(!DaemonAbsence.silent.isTransient)
    }

    @Test("only a daemon that is not there is called not installed")
    func notInstalled() {
        #expect(DaemonAbsence.of(.notInstalled, quietFor: 0) == .notInstalled)
        #expect(DaemonAbsence.of(.notInstalled, quietFor: 3600) == .notInstalled)
        #expect(DaemonAbsence.of(.failed("no"), quietFor: 0) == .failed("no"))
    }
}
