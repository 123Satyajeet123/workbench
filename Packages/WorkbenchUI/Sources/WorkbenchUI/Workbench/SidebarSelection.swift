import WorkbenchCore

/// The pages of the main window: Mochi (the day), Echo (calls), Runs, and one page per machine. A fixed page's name,
/// role and face live here, the one place to rename it; a machine's come from its record.
enum SidebarSelection: Hashable, Identifiable, RawRepresentable {
    case day, review, calls, catalog, runs
    case machine(Int64)

    static let fixed: [Self] = [.day, .review, .calls, .catalog, .runs]

    init?(rawValue: String) {
        switch rawValue {
        case "day": self = .day
        case "review": self = .review
        case "calls": self = .calls
        case "catalog": self = .catalog
        case "runs": self = .runs
        default:
            guard rawValue.hasPrefix("machine:"), let id = Int64(rawValue.dropFirst("machine:".count)) else {
                return nil
            }
            self = .machine(id)
        }
    }

    var rawValue: String {
        switch self {
        case .day: "day"
        case .review: "review"
        case .calls: "calls"
        case .catalog: "catalog"
        case .runs: "runs"
        case .machine(let id): "machine:\(id)"
        }
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "Mochi"
        case .review: "Review"
        case .calls: "Echo"
        case .catalog: "Team"
        case .runs: "Runs"
        case .machine: "Machine"
        }
    }

    var role: String {
        switch self {
        case .day: "Your day"
        case .review: "Everything to check"
        case .calls: "Calls"
        case .catalog: "Shared by your team"
        case .runs: "Model use and trust"
        case .machine: ""
        }
    }

    /// The face of a fixed helper. Runs is a tool, not a helper, so it has none.
    var look: Mascot.Look? {
        switch self {
        case .day: Mascot.Look(hue: 0.04, wear: .crown)
        case .calls: Mascot.Look(hue: 0.76, wear: .headphones)
        case .review, .catalog, .runs, .machine: nil
        }
    }
}

extension Mascot.Look {
    /// A machine's face: the built-in team machine keeps Pip's blue; every other machine gets a hue of its own.
    static func of(_ machine: Machine) -> Mascot.Look {
        let hue = machine.task == HelperSpec.team.task ? 0.55 : Double((machine.id &* 47) % 100) / 100
        return Mascot.Look(hue: hue, wear: .antenna)
    }
}
