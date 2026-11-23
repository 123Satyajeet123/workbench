import CaptureService
import Foundation
import Kernel
import LocalSources

/// Which data the app opens: the person's own, or the synthetic demo. The choice is saved outside both stores and read
/// once, at launch, to pick the store folder. Every door the app has to the rest of this Mac is a property here, so the
/// demo cannot reach one by a different code path.
enum Profile: String, CaseIterable {
    case yours, demo

    static let defaultsKey = "profile"
    /// The builder writes this file last. A demo folder without it is missing or half built, and never opens.
    static let builtMarker = "synthetic-demo.json"

    static func saved(in defaults: UserDefaults = .standard) -> Profile {
        defaults.string(forKey: defaultsKey).flatMap(Profile.init(rawValue:)) ?? .yours
    }

    /// Said by the builder when the demo folder is whole.
    static func markDemoBuilt(in folder: URL) throws {
        try Data(#"{"synthetic":true}"#.utf8).write(to: folder.appending(path: builtMarker))
    }

    func save(in defaults: UserDefaults = .standard) { defaults.set(rawValue, forKey: Self.defaultsKey) }

    var isDemo: Bool { self == .demo }

    var defaultFolder: URL {
        URL.applicationSupportDirectory.appending(path: isDemo ? "Workbench Demo" : "Workbench")
    }

    /// Why this profile cannot open `folder`, or nil when it can. A demo folder that was deleted or never finished
    /// must not open as an empty store: the person would see onboarding on a screen that says demo.
    func refusal(for folder: URL) -> String? {
        guard isDemo, !FileManager.default.fileExists(atPath: folder.appending(path: Self.builtMarker).path) else {
            return nil
        }
        return "The demo data is missing. Open your own data, or build the demo again."
    }

    var startsCapture: Bool { !isDemo }

    /// The WhatsApp data the machines read: this Mac's own, or the synthetic chats inside the demo folder.
    func whatsAppContainer(in folder: URL) -> URL {
        isDemo ? folder.appending(path: "WhatsApp") : WhatsAppChatReader.defaultContainer
    }

    /// The person who owns what is read. The demo has a fixed name that is nobody, so no source id of a real person is
    /// made for a demo line and the Keychain is never asked.
    func owner(secrets: SecretStore) -> Result<PersonID, any Error> {
        isDemo ? Result { try PersonID("p-synthetic-demo") } : OwnerIdentity.result(secrets: secrets)
    }

    var notifier: any Notifier { isDemo ? QuietNotifier() : SystemNotifier() }

    /// Where the daily notification count and quiet hours live. The demo's own, so it never uses up the real cap.
    var notificationDefaults: UserDefaults {
        isDemo ? UserDefaults(suiteName: "com.hizen.workbench.demo") ?? .standard : .standard
    }

    var calendar: (any CalendarEvents)? { isDemo ? nil : EventKitCalendar() }

    var reminders: any ReminderList { isDemo ? QuietReminders() : AppleReminders() }
}

/// Asks macOS for nothing and shows nothing. Used where a profile may not notify.
struct QuietNotifier: Notifier {
    func authorize() async -> SystemAccess { .allowed }
    func post(title: String, body: String, page: SidebarSelection) async throws {}
    func post(_ notice: FactNotice) async throws {}
}

/// Never reaches the Reminders app: the demo adds nothing to it.
struct QuietReminders: ReminderList {
    func authorize() async -> SystemAccess { .failed("Reminders are off in the demo.") }
    func add(title: String, notes: String) throws {}
}
