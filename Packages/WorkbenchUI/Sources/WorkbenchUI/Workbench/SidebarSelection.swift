import CaptureService
import Foundation
import WorkbenchCore

/// The pages of the main window: Today (the home), People, Projects, Echo (calls), Mochi, Crew, and one page per
/// machine. A fixed page's name, role and face live here, the one place to rename it; a machine's come from its record.
/// `advanced` is not a page of the window: it names Settings › Advanced, so an old `runs` link still opens it.
enum SidebarSelection: Hashable, Identifiable, RawRepresentable {
    case day, people, projects, mochi, crew, review, calls, deals, catalog, advanced
    case machine(Int64)

    static let fixed: [Self] = [.day, .people, .projects, .mochi, .crew, .review, .calls, .deals, .catalog, .advanced]

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
        case "advanced", "runs": self = .advanced
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
        case .advanced: "advanced"
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
        case .crew: "Crew"
        case .review: "Review"
        case .calls: "Echo"
        case .deals: "Deals"
        case .catalog: "Team"
        case .advanced: "Advanced"
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
        case .advanced: "Model use and quality numbers"
        case .machine: ""
        }
    }

    /// What a sidebar page is for, shown under its title until the person closes it. Nil for what is not a sidebar page.
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
        case .advanced, .machine: nil
        }
    }

    /// The face of a fixed helper. The other pages are tools, not helpers, so they have none. Today is Mochi's brief of
    /// the day, so it wears Mochi's face.
    var look: Mascot.Look? {
        switch self {
        case .day, .mochi: .mochi
        case .calls: .echo
        case .people, .projects, .crew, .review, .deals, .catalog, .advanced, .machine: nil
        }
    }
}

extension Mascot.Look {
    static let mochi = Mascot.Look(hue: 0.04, wear: .crown)
    static let pip = Mascot.Look(hue: 0.55, wear: .antenna)
    static let echo = Mascot.Look(hue: 0.76, wear: .headphones)

    /// A machine's face: the built-in team machine keeps Pip's blue; every other machine gets a hue of its own.
    static func of(_ machine: Machine) -> Mascot.Look {
        machine.task == HelperSpec.team.task
            ? .pip : Mascot.Look(hue: Double((machine.id &* 47) % 100) / 100, wear: .antenna)
    }
}
