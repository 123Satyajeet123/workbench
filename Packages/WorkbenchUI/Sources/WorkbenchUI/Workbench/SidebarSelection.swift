import CaptureService
import Foundation
import WorkbenchCore

enum SidebarSelection: Hashable, Identifiable, RawRepresentable {
    case day, people, projects, mochi, crew, review, calls, deals, catalog, usage, settings
    case machine(Int64)

    static let fixed: [Self] = [
        .day, .people, .projects, .mochi, .crew, .review, .calls, .deals, .catalog, .usage, .settings,
    ]

    init?(rawValue: String) {
        switch rawValue {
        case "day": self = .day
        case "people": self = .people
        case "projects": self = .projects
        case "mochi": self = .mochi
        case "crew": self = .crew
        case "review": self = .review
        case "calls": self = .calls
        case "deals": self = .deals
        case "catalog": self = .catalog
        case "usage", "advanced", "runs": self = .usage
        case "settings": self = .settings
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
        case .crew: "crew"
        case .review: "review"
        case .calls: "calls"
        case .deals: "deals"
        case .catalog: "catalog"
        case .usage: "usage"
        case .settings: "settings"
        case .machine(let id): "machine:\(id)"
        }
    }

    var id: String { rawValue }

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
        case .crew: "Crew"
        case .review: "Review"
        case .calls: "Echo"
        case .deals: "Deals"
        case .catalog: "Team"
        case .usage: "Usage"
        case .settings: "Settings"
        case .machine: "Machine"
        }
    }

    var role: String {
        switch self {
        case .day: "What needs you"
        case .people: "Facts by person"
        case .projects: "Facts by project"
        case .mochi: "Brief and timeline"
        case .crew: "Your machines"
        case .review: "Everything to check"
        case .calls: "Calls"
        case .deals: "Shared work"
        case .catalog: "Shared by your team"
        case .usage: "Model cost and Claude plan limits"
        case .settings: "Your name, model and what Workbench captures"
        case .machine: ""
        }
    }

    var intro: String? {
        switch self {
        case .day:
            "Your day at a glance: what needs you, today's meetings, your team, your projects and yesterday's brief."
        case .people:
            "What each person on your team planned, finished, got stuck on or promised."
        case .projects:
            "Where each project stands: decisions, open questions, blockers and promises."
        case .calls:
            "Each call stays on this Mac for \(Int(CaptureService.retention / 86_400)) days. A call that could not be saved says why."
        case .deals:
            "Your team's deals, one column per stage. Open a deal to see where it came from and what it needs next."
        case .mochi:
            "A brief of your day and a timeline of what you worked on. After \(Mochi.minimumDays) work days, Mochi suggests machines for work you repeat."
        case .crew:
            "Each machine reads one source for one job, like Pip with your team's chats. Add one with + in the sidebar."
        case .review:
            "Everything found that you haven't checked yet. Your marks teach each machine and decide when it can run on its own."
        case .catalog:
            "What your teammates shared with you: their days and their machines."
        case .usage, .settings, .machine: nil
        }
    }

    var look: Mascot.Look? {
        switch self {
        case .day, .mochi: .mochi
        case .calls: .echo
        case .people, .projects, .crew, .review, .deals, .catalog, .usage, .settings, .machine: nil
        }
    }
}

extension Mascot.Look {
    static let mochi = Mascot.Look(hue: 0.04, wear: .crown)
    static let pip = Mascot.Look(hue: 0.55, wear: .antenna)
    static let echo = Mascot.Look(hue: 0.76, wear: .headphones)

    static func of(_ machine: Machine) -> Mascot.Look {
        machine.task == HelperSpec.team.task
            ? .pip : Mascot.Look(hue: Double((machine.id &* 47) % 100) / 100, wear: .antenna)
    }
}
