import AppKit
import UserNotifications

/// Whether macOS lets Workbench use something the founder controls (notifications, Reminders), and why not.
enum SystemAccess: Equatable {
    case allowed
    /// The founder said no, now or before; only System Settings can change it.
    case blocked
    /// macOS refused with an error, in its words.
    case failed(String)
}

/// Shows a message to the founder outside the window. Silent: no notification plays a sound.
protocol Notifier {
    /// Asks macOS once when it has not asked before; otherwise reports what the founder chose.
    func authorize() async -> SystemAccess
    func post(title: String, body: String) async throws
}

struct SystemNotifier: Notifier {
    func authorize() async -> SystemAccess {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional: return .allowed
        case .denied: return .blocked
        case .notDetermined, .ephemeral: break
        @unknown default: break
        }
        do {
            return try await center.requestAuthorization(options: [.alert]) ? .allowed : .blocked
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func post(title: String, body: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil
        try await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// Workbench's own page in System Settings › Notifications.
    static func openSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }
}
