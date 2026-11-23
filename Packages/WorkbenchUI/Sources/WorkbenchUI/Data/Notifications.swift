import Foundation
import Observation
import os

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

    func whenAllowed(_ turnOn: @escaping () -> Void) async {
        if await isAllowed() {
            turnOn()
        } else if blocked {
            waiting.append(turnOn)
        }
    }

    func isAllowed() async -> Bool {
        switch await notifier.authorize() {
        case .allowed:
            blocked = false
            problem = nil
            return true
        case .blocked:
            blocked = true
            return false
        case .failed(let reason):
            problem = "macOS refused notifications: \(reason)"
            return false
        }
    }

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
