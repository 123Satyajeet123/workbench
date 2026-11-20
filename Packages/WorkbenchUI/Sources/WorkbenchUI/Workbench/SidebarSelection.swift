import Foundation
import WorkbenchCore

/// The pages of the main window: Today (the home), People, Projects, Echo (calls), Mochi, Runs, and one page per
/// machine. A fixed page's name, role and face live here, the one place to rename it; a machine's come from its record.
enum SidebarSelection: Hashable, Identifiable, RawRepresentable {
    case day, people, projects, mochi, review, calls, deals, catalog, runs
    case machine(Int64)

    static let fixed: [Self] = [.day, .people, .projects, .mochi, .review, .calls, .deals, .catalog, .runs]

    init?(rawValue: String) {
        switch rawValue {
        case "day": self = .day
        case "people": self = .people
        case "projects": self = .projects
        case "mochi": self = .mochi
        case "review": self = .review
        case "calls": self = .calls
        case "deals": self = .deals
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
        case .people: "people"
        case .projects: "projects"
        case .mochi: "mochi"
        case .review: "review"
        case .calls: "calls"
        case .deals: "deals"
        case .catalog: "catalog"
        case .runs: "runs"
        case .machine(let id): "machine:\(id)"
        }
    }

    var id: String { rawValue }

    /// The link that opens this page from outside the window: a notification, the island. macOS hands it to the
    /// app, which shows the window on this page.
    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "page", value: rawValue)]
        return components.url!
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme, url.host() == "open",
            let page = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: {
                $0.name == "page"
            })?.value
        else { return nil }
        self.init(rawValue: page)
    }

    static let scheme = "workbench"

    var title: String {
        switch self {
        case .day: "Today"
        case .people: "People"
        case .projects: "Projects"
        case .mochi: "Mochi"
        case .review: "Review"
        case .calls: "Echo"
        case .deals: "Deals"
        case .catalog: "Team"
        case .runs: "Runs"
        case .machine: "Machine"
        }
    }

    var role: String {
        switch self {
        case .day: "What needs you"
        case .people: "Facts by person"
        case .projects: "Facts by project"
        case .mochi: "Brief, timeline and proposals"
        case .review: "Everything to check"
        case .calls: "Calls"
        case .deals: "Shared work"
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
        case .people, .projects, .mochi, .review, .deals, .catalog, .runs, .machine: nil
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
