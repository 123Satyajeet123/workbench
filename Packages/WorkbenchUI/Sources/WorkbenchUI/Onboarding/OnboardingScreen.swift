enum OnboardingScreen: String, CaseIterable, Codable, Identifiable {
    case welcome, you, team, connect, setup, watchlist, firstLook, done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .welcome: "Workbench"
        case .you: "What should we call you?"
        case .team: "Your team"
        case .connect: "Connect Workbench"
        case .setup: "Set up your machines"
        case .watchlist: "Companies you follow"
        case .firstLook: "A first look"
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
        case .watchlist:
            "Name the companies you invested in and the ones you passed on. Workbench watches the news for them."
        case .firstLook:
            "See what your machines find in your last few days, so you do not start with an empty page. Mark a few to teach them."
        case .done: "Open \(SidebarSelection.mochi.title) to read your first day."
        }
    }

    var look: Mascot.Look? {
        switch self {
        case .you, .setup, .watchlist, .firstLook, .done: .mochi
        case .team: .pip
        case .welcome, .connect: nil
        }
    }
}
