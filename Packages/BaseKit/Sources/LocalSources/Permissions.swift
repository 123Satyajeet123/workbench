import EventKit
import Foundation

public enum SystemAccess: Sendable, Equatable {
    case allowed
    case blocked
    case failed(String)
}

public enum PrivacyPane: String, Sendable {
    case accessibility = "Privacy_Accessibility"
    case microphone = "Privacy_Microphone"
    case calendars = "Privacy_Calendars"
    case reminders = "Privacy_Reminders"
    case fullDiskAccess = "Privacy_AllFiles"

    public var url: URL { URL(string: "x-apple.systempreferences:com.apple.preference.security?\(rawValue)")! }
}

public enum EventKitAccess {
    public static func request(_ type: EKEntityType) async -> SystemAccess {
        let store = EKEventStore()
        switch EKEventStore.authorizationStatus(for: type) {
        case .fullAccess: return .allowed
        case .denied, .restricted, .writeOnly: return .blocked
        case .notDetermined: break
        @unknown default: break
        }
        do {
            let granted =
                type == .event
                ? try await store.requestFullAccessToEvents() : try await store.requestFullAccessToReminders()
            return granted ? .allowed : .blocked
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
