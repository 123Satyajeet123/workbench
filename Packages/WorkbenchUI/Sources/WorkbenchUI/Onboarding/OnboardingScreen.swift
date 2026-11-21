enum OnboardingScreen: String, CaseIterable, Identifiable {
    case welcome, you, team, connect, done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .welcome: "Workbench"
        case .you: "What should we call you?"
        case .team: "Your team"
        case .connect: "Connect Workbench"
        case .done: "You’re set"
        }
    }

    var lead: String {
        switch self {
        case .welcome: "Your day, your team and your calls, turned into what needs you."
        case .you: "Workbench uses your name to tell your messages from your team's. It stays on this Mac."
        case .team:
            "Name your team and add the people you work with. Workbench links what it finds to them. You can change this later in Settings."
        case .connect:
            "Turn on what you want Workbench to read. Each stays off until you turn it on, and you can change it later in Settings."
        case .done: "Open \(SidebarSelection.day.title) to read your first day."
        }
    }

    var look: Mascot.Look? {
        switch self {
        case .you, .done: .mochi
        case .team: .pip
        case .welcome, .connect: nil
        }
    }
}
