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

    init(notifier: Notifier = SystemNotifier()) {
        self.notifier = notifier
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

    func post(title: String, body: String) async throws {
        try await notifier.post(title: title, body: body)
    }

    /// Posts without waiting, for a caller that has no page to show a failure on. A failure goes to the log.
    func announce(title: String, body: String) {
        Task {
            do {
                try await post(title: title, body: body)
            } catch {
                Self.log.error("Could not show \"\(title, privacy: .public)\": \(error.localizedDescription)")
            }
        }
    }
}
