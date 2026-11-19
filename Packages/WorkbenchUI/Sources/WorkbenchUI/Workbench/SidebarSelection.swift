/// The pages of the main window. Cases name the job; `title` is the helper's name, the one place to rename it.
enum SidebarSelection: String, Hashable, CaseIterable, Identifiable {
    case day, team, calls, runs

    static let crew: [Self] = [.team, .calls]

    var id: Self { self }

    var title: String {
        switch self {
        case .day: "Mochi"
        case .team: "Pip"
        case .calls: "Echo"
        case .runs: "Runs"
        }
    }

    var role: String {
        switch self {
        case .day: "Your day"
        case .team: "Team updates"
        case .calls: "Calls"
        case .runs: "Model use and precision"
        }
    }

    /// The helper's face. Runs is a tool, not a helper, so it has none.
    var look: Mascot.Look? {
        switch self {
        case .day: Mascot.Look(hue: 0.04, wear: .crown)
        case .team: Mascot.Look(hue: 0.55, wear: .antenna)
        case .calls: Mascot.Look(hue: 0.76, wear: .headphones)
        case .runs: nil
        }
    }
}
