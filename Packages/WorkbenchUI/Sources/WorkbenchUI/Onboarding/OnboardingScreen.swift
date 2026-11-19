enum OnboardingScreen: String, CaseIterable, Identifiable {
    case welcome, you, sources, done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .welcome: "Workbench"
        case .you: "About you"
        case .sources: "What may Workbench read?"
        case .done: "You’re set"
        }
    }

    var lead: String {
        switch self {
        case .welcome:
            "Workbench keeps your team's plans, your calls and your day in one place, and shows how well its model reads them."
        case .you: "Workbench uses your name to tell your messages from your team's. It stays on this Mac."
        case .sources: "Each is off until you turn it on. Your team's WhatsApp group is chosen later, on the Team page."
        case .done: "Open Team to choose your group and read your first day."
        }
    }
}
