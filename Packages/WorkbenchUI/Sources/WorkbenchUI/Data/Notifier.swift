import AppKit
import LocalSources
import UserNotifications

/// Shows a message to the founder outside the window. Silent: no notification plays a sound.
protocol Notifier {
    /// Asks macOS once when it has not asked before; otherwise reports what the founder chose.
    func authorize() async -> SystemAccess
    func post(title: String, body: String, page: SidebarSelection) async throws
    /// Shows one fact with the marks its `offer` allows. Posting the same fact again replaces its notification.
    func post(_ notice: FactNotice) async throws
    /// Takes the fact's notification out of Notification Centre, because the fact is handled.
    func removeDelivered(itemID: Int64)
}

extension Notifier {
    func post(_ notice: FactNotice) async throws {
        try await post(title: notice.title, body: notice.source, page: notice.page)
    }

    func removeDelivered(itemID: Int64) {}
}

/// A fact to show outside the window. It holds the fact title and the source name, and nothing else.
struct FactNotice: Equatable, Sendable {
    /// Which marks the notification offers.
    enum Offer: String, CaseIterable, Sendable {
        /// An open fact: Done and Snooze 1 day.
        case open
        /// A random check of a fact nobody has marked: Right and Wrong.
        case check

        var category: String { "fact.\(rawValue)" }

        var actions: [NotificationAction] {
            switch self {
            case .open: [.done, .snooze1]
            case .check: [.right, .wrong]
            }
        }
    }

    let itemID: Int64
    let title: String
    let source: String
    let offer: Offer
    /// What a click on the notification opens until the window can open the fact itself.
    var page = SidebarSelection.day

    var identifier: String { Self.identifier(of: itemID) }

    static func identifier(of itemID: Int64) -> String { "fact-\(itemID)" }

    /// Silent. Its text is the fact title and the source name; the user info holds only the ids a reply needs.
    var content: UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = source
        content.sound = nil
        content.categoryIdentifier = offer.category
        content.userInfo = [SystemNotifier.pageKey: page.url.absoluteString, SystemNotifier.factKey: Int(itemID)]
        return content
    }
}

/// A mark chosen on a notification. The raw value is the action id macOS reports.
enum NotificationAction: String, CaseIterable, Sendable {
    case done, snooze1, right, wrong

    var title: String {
        switch self {
        case .done: "Done"
        case .snooze1: "Snooze 1 day"
        case .right: "Right"
        case .wrong: "Wrong"
        }
    }
}

struct NotificationAnswer: Equatable, Sendable {
    let itemID: Int64
    let action: NotificationAction
}

/// What the founder did with a notification: chose a mark on it, or clicked its body.
enum NotificationReply: Equatable, Sendable {
    case answer(NotificationAnswer)
    case open(itemID: Int64)

    static let bodyClick = UNNotificationDefaultActionIdentifier

    /// Nil for a notification that is not about a fact, and for any other action, such as dismiss.
    init?(actionID: String, userInfo: [AnyHashable: Any]) {
        guard let itemID = userInfo[SystemNotifier.factKey] as? Int else { return nil }
        if actionID == Self.bodyClick {
            self = .open(itemID: Int64(itemID))
        } else if let action = NotificationAction(rawValue: actionID) {
            self = .answer(NotificationAnswer(itemID: Int64(itemID), action: action))
        } else {
            return nil
        }
    }
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

    func post(_ notice: FactNotice) async throws {
        try await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: notice.identifier, content: notice.content, trigger: nil))
    }

    func removeDelivered(itemID: Int64) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: [FactNotice.identifier(of: itemID)])
    }

    /// Registers the marks each kind of fact notification offers. macOS needs this at every launch, before it
    /// hands the app a response, including a launch that an action caused.
    static func registerCategories() {
        UNUserNotificationCenter.current().setNotificationCategories(
            Set(
                [FactNotice.Offer.open, .check].map { offer in
                    UNNotificationCategory(
                        identifier: offer.category,
                        actions: offer.actions.map {
                            UNNotificationAction(identifier: $0.rawValue, title: $0.title, options: [])
                        },
                        intentIdentifiers: [])
                }))
    }

    static let pageKey = "page"
    static let factKey = "fact"

    static func reply(to response: UNNotificationResponse) -> NotificationReply? {
        NotificationReply(
            actionID: response.actionIdentifier, userInfo: response.notification.request.content.userInfo)
    }

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
