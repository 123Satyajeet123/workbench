import UserNotifications

/// Shows a message to the founder outside the window. Silent: no notification plays a sound.
protocol Notifier {
    /// Asks macOS for permission once; the founder answers in the system dialog.
    func prepare() async -> Bool
    func post(title: String, body: String) async throws
}

struct SystemNotifier: Notifier {
    func prepare() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])) ?? false
    }

    func post(title: String, body: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil
        try await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
