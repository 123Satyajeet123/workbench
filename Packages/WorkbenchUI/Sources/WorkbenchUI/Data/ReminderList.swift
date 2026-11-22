import AppKit
import EventKit
import LocalSources

/// The founder's Reminders app. Workbench adds to it only when the founder clicks.
protocol ReminderList {
    /// Asks macOS once when it has not asked before; otherwise reports what the founder chose.
    func authorize() async -> SystemAccess
    func add(title: String, notes: String) throws
}

struct AppleReminders: ReminderList {
    struct NoList: LocalizedError {
        var errorDescription: String? { "Reminders has no default list." }
    }

    private let store = EKEventStore()

    func authorize() async -> SystemAccess { await EventKitAccess.request(.reminder) }

    func add(title: String, notes: String) throws {
        guard let list = store.defaultCalendarForNewReminders() else { throw NoList() }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = list
        try store.save(reminder, commit: true)
    }
}
