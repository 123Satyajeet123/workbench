import CaptureService
import Foundation
import WorkbenchCore

/// The pages of the main window: Mochi (the home), People, Projects, Calls (Echo), Timeline, Overview (the crew), one
/// page per machine and one per work object of the tree. A fixed page's name, role and face live here, the one place to
/// rename it; a machine's and a work object's come from their records.
/// `day` and `review` are old names of Mochi's page, and `advanced` and `runs` of the Usage page, so an old link still
/// opens them.
enum SidebarSelection: Hashable, Identifiable, RawRepresentable {
    case mochi, people, projects, calls, timeline, crew, deals, catalog, usage, settings
    case machine(Int64)
    case page(WorkObjectID)

    static let fixed: [Self] = [
        .mochi, .people, .projects, .calls, .timeline, .crew, .deals, .catalog, .usage, .settings,
    ]

    init?(rawValue: String) {
        switch rawValue {
        case "mochi", "day", "review": self = .mochi
        case "people": self = .people
        case "projects": self = .projects
        case "timeline": self = .timeline
        case "crew": self = .crew
        case "calls": self = .calls
        case "deals": self = .deals
        case "catalog": self = .catalog
        case "usage", "advanced", "runs": self = .usage
        case "settings": self = .settings
        default:
            if rawValue.hasPrefix("machine:"), let id = Int64(rawValue.dropFirst("machine:".count)) {
                self = .machine(id)
            } else if rawValue.hasPrefix("page:"), rawValue.count > "page:".count {
                self = .page(String(rawValue.dropFirst("page:".count)))
            } else {
                return nil
            }
        }
    }

    var rawValue: String {
        switch self {
        case .mochi: "mochi"
        case .people: "people"
        case .projects: "projects"
        case .timeline: "timeline"
        case .crew: "crew"
        case .calls: "calls"
        case .deals: "deals"
        case .catalog: "catalog"
        case .usage: "usage"
        case .settings: "settings"
        case .machine(let id): "machine:\(id)"
        case .page(let id): "page:\(id)"
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
        case .mochi: "Mochi"
        case .people: "People"
        case .projects: "Projects"
        case .timeline: "Timeline"
        case .crew: "Overview"
        case .calls: "Calls"
        case .deals: "Deals"
        case .catalog: "Team"
        case .usage: "Usage"
        case .settings: "Settings"
        case .machine: "Machine"
        case .page: "Page"
        }
    }

    var role: String {
        switch self {
        case .mochi: "Your day, from every machine"
        case .people: "Facts by person"
        case .projects: "Facts by project"
        case .timeline: "What you did, across apps"
        case .crew: "Every machine that works for Mochi"
        case .calls: "Calls Echo recorded"
        case .deals: "Shared work"
        case .catalog: "Shared by your team"
        case .usage: "Model cost and Claude plan limits"
        case .settings: "Your name, model and what Workbench captures"
        case .machine, .page: ""
        }
    }

    /// What a sidebar page is for, shown under its title until the person closes it. Nil for what is not a sidebar page.
    var intro: String? {
        switch self {
        case .people:
            "What each person on your team planned, finished, got stuck on or promised."
        case .projects:
            "Where each project stands: decisions, open questions, blockers and promises."
        case .calls:
            "Each call stays on this Mac for \(Int(CapturePolicy.retention / 86_400)) days. A call that could not be saved says why."
        case .deals:
            "Your team's deals, one column per stage. Open a deal to see where it came from and what it needs next."
        case .mochi:
            "Mochi gathers what every machine found: what needs you, today's meetings, follow-ups from calls, your team and your projects. After \(Mochi.minimumDays) work days, Mochi suggests machines for work you repeat."
        case .timeline:
            "Your day in blocks of work. Each block joins the windows you used for one task, even across apps, read from your screen."
        case .crew:
            "Each machine reads one source for one job and reports to Mochi, like Pip with your team's chats or Echo with your calls. Add one with New machine… in a folder's menu in the sidebar."
        case .catalog:
            "What your teammates shared with you: their days and their machines."
        case .usage, .settings, .machine, .page: nil
        }
    }

    /// The SF Symbol of a page that has no face. A machine's and a work object's come from their records.
    var symbol: String {
        switch self {
        case .mochi: "sparkle"
        case .people: "person.2"
        case .projects: "square.stack.3d.up"
        case .timeline: "clock"
        case .crew: "rectangle.grid.2x2"
        case .calls: "headphones"
        case .deals: "rectangle.3.group"
        case .catalog: "person.crop.rectangle.stack"
        case .usage: "chart.xyaxis.line"
        case .settings: "gearshape"
        case .machine: "gearshape.2"
        case .page: "doc.text"
        }
    }

    /// The face of a fixed helper. The other pages are tools, not helpers, so they have none.
    var look: Mascot.Look? {
        switch self {
        case .mochi: .mochi
        case .calls: .echo
        case .people, .projects, .timeline, .crew, .deals, .catalog, .usage, .settings, .machine, .page: nil
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
