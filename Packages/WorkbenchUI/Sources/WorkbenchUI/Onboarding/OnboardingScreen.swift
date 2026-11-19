enum OnboardingScreen: String, CaseIterable, Identifiable {
    case welcome, you, team, sources, done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .welcome: "Workbench"
        case .you: "About you"
        case .team: "Your team"
        case .sources: "What may Workbench read?"
        case .done: "You’re set"
        }
    }

    var lead: String {
        switch self {
        case .welcome:
            "Workbench learns your day from what you allow it to see. Its helpers turn your repeated work into items you check, and each helper earns your trust from your marks."
        case .you: "Workbench uses your name to tell your messages from your team's. It stays on this Mac."
        case .team:
            "Name your team and add the people you work with. Machines link what they find to these people. You can change this later in Settings."
        case .sources:
            "Each is off until you turn it on. Turn on Screen so \(SidebarSelection.day.title) can write your timeline. Your team's WhatsApp group is chosen later, in \(MachineTemplate.team.name)."
        case .done:
            "Open \(SidebarSelection.day.title) and read your first day. To follow your team, choose its group in \(MachineTemplate.team.name)."
        }
    }
}
