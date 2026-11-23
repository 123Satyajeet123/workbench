import AppKit
import Foundation
import Observation
import os

/// Whether macOS lets Workbench notify: one answer for the whole app. Every feature that notifies asks here, and the
/// answer is checked again whenever the app becomes active, so allowing in System Settings takes effect at once and
/// what waited for it turns on.
@Observable
final class Notifications {
    private(set) var blocked = false
    private(set) var problem: String?

    private static let log = Logger(subsystem: "Workbench", category: "notifications")

    @ObservationIgnored let notifier: Notifier
    @ObservationIgnored private var waiting: [() -> Void] = []
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let windowInFront: @MainActor () -> Bool

    init(
        notifier: Notifier = SystemNotifier(), defaults: UserDefaults = .standard,
        clock: @escaping () -> Date = Date.init,
        windowInFront: @escaping @MainActor () -> Bool = Notifications.appWindowIsInFront
    ) {
        self.notifier = notifier
        self.defaults = defaults
        self.clock = clock
        self.windowInFront = windowInFront
    }

    static func appWindowIsInFront() -> Bool {
        NSApp.isActive && NSApp.keyWindow?.isMainWindow == true
    }

    /// Shows a fact when the gate allows it. Returns whether it showed one.
    @discardableResult
    func notify(_ notice: FactNotice, itemOpen: Bool) async throws -> Bool {
        try await gated(itemOpen: itemOpen) { try await self.notifier.post(notice) }
    }

    /// Shows one summary, such as "3 things need you today", under the same daily cap, quiet hours and window rule
    /// as fact notifications. A click opens `page`. Returns whether it showed one.
    @discardableResult
    func notifySummary(title: String, body: String, page: SidebarSelection) async throws -> Bool {
        try await gated(itemOpen: true) { try await self.notifier.post(title: title, body: body, page: page) }
    }

    /// Posts when macOS and the gate allow it. A notification that macOS blocks, that the gate holds back, or that
    /// fails to post does not count against the daily cap.
    private func gated(itemOpen: Bool, _ post: () async throws -> Void) async throws -> Bool {
        let access = await notifier.authorize()
        blocked = access == .blocked
        guard access == .allowed else { return false }
        let now = clock()
        var sent = DailyCount.stored(in: defaults)
        guard
            NotificationGate.shows(
                now: now, windowInFront: windowInFront(), sentToday: sent.sent(on: now),
                policy: .saved(in: defaults), itemOpen: itemOpen)
        else { return false }
        sent.record(at: now)
        sent.store(in: defaults)
        do {
            try await post()
        } catch {
            var kept = DailyCount.stored(in: defaults)
            kept.withdraw()
            kept.store(in: defaults)
            throw error
        }
        return true
    }

    /// Removes the notification of a fact that was handled, in the window, the menu bar or a notification.
    func clear(itemID: Int64) {
        notifier.removeDelivered(itemID: itemID)
    }

    /// Runs `turnOn` when macOS allows notifications: now, or once the founder allows them in System Settings.
    func whenAllowed(_ turnOn: @escaping () -> Void) async {
        switch await notifier.authorize() {
        case .allowed:
            blocked = false
            problem = nil
            turnOn()
        case .blocked:
            blocked = true
            waiting.append(turnOn)
        case .failed(let reason):
            problem = "macOS refused notifications: \(reason)"
        }
    }

    /// Asks macOS again; once the founder has answered, macOS shows no prompt.
    func recheck() async {
        guard blocked, case .allowed = await notifier.authorize() else { return }
        blocked = false
        let pending = waiting
        waiting = []
        for turnOn in pending { turnOn() }
    }

    func post(title: String, body: String, page: SidebarSelection) async throws {
        try await notifier.post(title: title, body: body, page: page)
    }

    /// Posts without waiting, for a caller that has no page to show a failure on. A failure goes to the log.
    func announce(title: String, body: String, page: SidebarSelection) {
        Task {
            do {
                try await post(title: title, body: body, page: page)
            } catch {
                Self.log.error("Could not show \"\(title, privacy: .public)\": \(error.localizedDescription)")
            }
        }
    }
}

/// Whether to show a notification now. One pure answer; every input is a reason to hold it back.
enum NotificationGate {
    static func shows(
        now: Date, windowInFront: Bool, sentToday: Int, policy: NotificationPolicy, itemOpen: Bool,
        calendar: Calendar = .current
    ) -> Bool {
        itemOpen && !windowInFront && sentToday < policy.dailyCap && !policy.quiet.contains(now, calendar: calendar)
    }
}

/// How many notifications went out on one day. The count restarts when the day changes.
struct DailyCount: Equatable {
    private(set) var day: Date
    private(set) var count: Int

    private static let dayKey = "notifications.sentDay"
    private static let countKey = "notifications.sentCount"

    static func stored(in defaults: UserDefaults) -> Self {
        Self(
            day: defaults.object(forKey: dayKey) as? Date ?? .distantPast, count: defaults.integer(forKey: countKey))
    }

    func store(in defaults: UserDefaults) {
        defaults.set(day, forKey: Self.dayKey)
        defaults.set(count, forKey: Self.countKey)
    }

    func sent(on now: Date, calendar: Calendar = .current) -> Int {
        calendar.isDate(day, inSameDayAs: now) ? count : 0
    }

    mutating func record(at now: Date, calendar: Calendar = .current) {
        count = sent(on: now, calendar: calendar) + 1
        day = now
    }

    mutating func withdraw() {
        count = max(0, count - 1)
    }
}

/// Holds what the founder did on a notification until the app can act on it. macOS can launch the app for an
/// action, and the response arrives before the window and its models exist.
final class NotificationReplies {
    private var waiting: [NotificationReply] = []

    var handler: ((NotificationReply) -> Void)? {
        didSet {
            guard let handler else { return }
            let pending = waiting
            waiting = []
            pending.forEach(handler)
        }
    }

    func receive(_ reply: NotificationReply) {
        if let handler { handler(reply) } else { waiting.append(reply) }
    }
}
