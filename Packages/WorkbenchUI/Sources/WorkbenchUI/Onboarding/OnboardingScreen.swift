enum OnboardingScreen: String, CaseIterable, Identifiable {
    case welcome, you, team, connect, setup, done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .welcome: "Workbench"
        case .you: "What should we call you?"
        case .team: "Your team"
        case .connect: "Connect Workbench"
        case .setup: "Set up your machines"
        case .done: "You’re set"
        }
    }

    var lead: String {
        switch self {
        case .welcome: "Your day, your team and your calls, turned into what needs you."
        case .you: "Workbench uses your name to tell your messages from your team's. It stays on this Mac."
        case .team:
            "Name your team and add the people you work with. Workbench links what it finds to them. Then choose what your team starts from. You can change the names later in Settings."
        case .connect:
            "Turn on what your team’s machines read. Each stays off until you turn it on, and you can change it later in Settings."
        case .setup:
            "Answer what you want. Skip keeps the values the template gives. You can change each one later on the machine’s page."
        case .done: "Open \(SidebarSelection.day.title) to read your first day."
        }
    }

    var look: Mascot.Look? {
        switch self {
        case .you, .setup, .done: .mochi
        case .team: .pip
        case .welcome, .connect: nil
        }
    }
}
