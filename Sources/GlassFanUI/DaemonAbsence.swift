import SwiftUI
import FanKit

/// What to say while the app has no daemon to talk to.
///
/// No connection used to mean "not installed", with an Install button - including
/// in the middle of an update, where the old daemon is taken down before the new
/// one starts and the socket is gone for a second or two. Asked for a password to
/// update, the user was then told fan control was not installed at all. Whether it
/// is installed is the installer's to say; the socket only says it is quiet.
enum DaemonAbsence: Equatable {
    /// The installer is running: its password dialog, then the swap.
    case working(DaemonInstaller.Job)
    /// Installed, and contact was lost a moment ago. Nearly always a restart.
    case connecting
    /// Installed, and quiet for longer than a restart takes.
    case silent
    case notInstalled
    case failed(String)

    /// Longer than an update keeps the daemon down: the old one saves its history
    /// on the way out and launchd is given a few tries to start the new one.
    static let patience: TimeInterval = 10

    static func of(_ status: DaemonInstaller.Status, quietFor: TimeInterval) -> DaemonAbsence {
        switch status {
        case .working(let job): return .working(job)
        case .notInstalled: return .notInstalled
        case .failed(let message): return .failed(message)
        case .installed, .outdated: return quietFor < patience ? .connecting : .silent
        }
    }

    /// Something is on its way back; nothing for the user to do yet.
    var isTransient: Bool {
        switch self {
        case .working, .connecting: return true
        case .silent, .notInstalled, .failed: return false
        }
    }

    var title: String {
        switch self {
        case .working(.install):   return L10n.t("Устанавливаю управление вентиляторами…", "Installing fan control…")
        case .working(.update):    return L10n.t("Обновляю управление вентиляторами…", "Updating fan control…")
        case .working(.reinstall): return L10n.t("Переустанавливаю управление вентиляторами…", "Reinstalling fan control…")
        case .working(.remove):    return L10n.t("Удаляю управление вентиляторами…", "Removing fan control…")
        case .connecting:          return L10n.t("Подключаюсь к управлению вентиляторами…", "Connecting to fan control…")
        case .silent:              return L10n.t("Управление вентиляторами не отвечает", "Fan control is not responding")
        case .notInstalled, .failed:
            return L10n.t("Управление вентиляторами не установлено", "Fan control is not installed yet")
        }
    }

    var detail: String {
        switch self {
        case .working(.remove):
            return L10n.t("Вентиляторы возвращаются под управление системы.",
                          "The fans go back to the system's own control.")
        case .working:
            return L10n.t("macOS спросит пароль, потом демон перезапустится — это пара секунд. Пока вентиляторами управляет система.",
                          "macOS asks for your password, then the daemon restarts, which takes a couple of seconds. Until then the system runs the fans.")
        case .connecting:
            return L10n.t("Демон установлен и, скорее всего, перезапускается.",
                          "It is installed and most likely restarting.")
        case .silent:
            return L10n.t("Демон установлен, но не отвечает. Обычно помогает переустановка — macOS спросит пароль.",
                          "It is installed but does not answer. Reinstalling usually brings it back; macOS will ask for your password.")
        case .notInstalled, .failed:
            return L10n.t("Крутить вентиляторы может только процесс с правами администратора. Приложение поставит его само — macOS спросит пароль.",
                          "Only a process with administrator rights can drive the fans. The app installs one itself; macOS will ask for your password.")
        }
    }
}

/// Hands its content what to say about the missing daemon, and looks again once a
/// quiet daemon has been quiet for longer than a restart takes - so "connecting"
/// turns into "not responding" without anything else on screen changing.
struct DaemonAbsenceReader<Content: View>: View {
    @Environment(DaemonClient.self) private var client
    @Environment(DaemonInstaller.self) private var installer
    @State private var now = Date()
    @ViewBuilder let content: (DaemonAbsence) -> Content

    var body: some View {
        content(.of(installer.status, quietFor: client.quietSince.map { now.timeIntervalSince($0) } ?? 0))
            .task(id: client.quietSince) {
                now = Date()
                guard let since = client.quietSince else { return }
                let left = DaemonAbsence.patience - now.timeIntervalSince(since)
                guard left > 0 else { return }
                try? await Task.sleep(for: .seconds(left))
                now = Date()
            }
    }
}

/// The live dot and "connected", "connecting…" or "offline".
struct ConnectionStatus: View {
    @Environment(DaemonClient.self) private var client
    var fontSize: CGFloat = 12
    var opacity: Double = 0.55

    var body: some View {
        HStack(spacing: 7) {
            LiveDot(active: client.isConnected)
            if client.isConnected {
                label(L10n.t("на связи", "connected"))
            } else {
                DaemonAbsenceReader { absence in
                    label(absence.isTransient ? L10n.t("подключаюсь…", "connecting…")
                                              : L10n.t("нет связи", "offline"))
                }
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: fontSize))
            .foregroundStyle(Palette.ink.opacity(opacity))
    }
}
