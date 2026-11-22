import AppKit
import EventKit

protocol ReminderList {
    func authorize() async -> SystemAccess
    func add(title: String, notes: String) throws
}

struct AppleReminders: ReminderList {
    struct NoList: LocalizedError {
        var errorDescription: String? { "Reminders has no default list." }
    }

    private let store = EKEventStore()

    func authorize() async -> SystemAccess {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: return .allowed
        case .denied, .restricted, .writeOnly: return .blocked
        case .notDetermined: break
        @unknown default: break
        }
        do {
            return try await store.requestFullAccessToReminders() ? .allowed : .blocked
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func add(title: String, notes: String) throws {
        guard let list = store.defaultCalendarForNewReminders() else { throw NoList() }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = list
        try store.save(reminder, commit: true)
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
            NSWorkspace.shared.open(url)
        }
    }
}
