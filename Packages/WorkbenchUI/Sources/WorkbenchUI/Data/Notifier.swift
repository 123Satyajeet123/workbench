import AppKit
import LocalSources
import UserNotifications

protocol Notifier {
    func authorize() async -> SystemAccess
    func post(title: String, body: String, page: SidebarSelection) async throws
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

    func post(title: String, body: String, page: SidebarSelection) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil
        content.userInfo = [Self.pageKey: page.url.absoluteString]
        try await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    static let pageKey = "page"

    static func page(of response: UNNotificationResponse) -> URL? {
        (response.notification.request.content.userInfo[pageKey] as? String).flatMap(URL.init(string:))
    }

    static func openSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }
}
