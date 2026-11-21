import WorkbenchCore

/// A machine a person can make: a built-in spec with a default name and a line on what it does.
struct MachineTemplate: Identifiable, Hashable {
    let spec: HelperSpec
    let name: String
    /// What kind of machine it is, under its name.
    let role: String
    let detail: String

    var id: String { spec.task }

    static let team = MachineTemplate(
        spec: .team, name: "Pip", role: "Team facts",
        detail:
            "Reads the WhatsApp chats you choose and keeps each person's plans, done work, blockers, commitments, decisions and questions, by project."
    )
    static let timeline = MachineTemplate(
        spec: .timeline, name: "Timeline", role: "Day timeline",
        detail: "Turns your screen sessions into blocks of work with the words they came from.")
    static let pages = MachineTemplate(
        spec: .pages, name: "Scout", role: "Page reader",
        detail:
            "Reads the text of pages you saw on sites you name, such as your mail or LinkedIn, and lists what needs your follow-up."
    )
    static let dealIntake = MachineTemplate(
        spec: .dealIntake, name: "Deal intake", role: "Deal intake",
        detail: "Reads your mail pages and lists each inbound startup, rated hot, warm or cold by your own criteria.")
    static let outbound = MachineTemplate(
        spec: .outbound, name: "Outbound", role: "Startup search",
        detail:
            "Searches the web for startups that fit your criteria, reads each page, and lists the ones worth a look with the words that show why. You add one to Deals or turn it down."
    )
    static let founderCheck = MachineTemplate(
        spec: .founderCheck, name: "Founder check", role: "Founder check",
        detail: "Reads founders' profile pages you opened and lists their roles, companies, exits and education.")
    static let companySignals = MachineTemplate(
        spec: .companySignals, name: "Page signals", role: "Company signals from pages",
        detail:
            "Reads news and social pages you saw and lists funding, hires, launches and risks of companies you follow.")
    static let newsSignals = MachineTemplate(
        spec: .newsSignals, name: "Signals", role: "News signals",
        detail:
            "Reads the Inc42 and YourStory feeds for your portfolio and the deals you passed on, and lists funding, layoffs, exits and other events, good and bad, with the words they came from."
    )
    static let derailment = MachineTemplate(
        spec: .derailment, name: "Sentinel", role: "Off-track watch",
        detail:
            "Follows the open commitments, questions and decisions of Pip and tells you what is overdue, quiet, blocked or drifting."
    )
    static let all = [
        team, timeline, pages, derailment, dealIntake, outbound, founderCheck, newsSignals, companySignals,
    ]
    /// The machines every store starts with; the others are made on request or from Mochi's proposals.
    static let seeded = [team, timeline]

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    static func of(_ machine: Machine) -> MachineTemplate? { all.first { $0.spec.task == machine.template } }
}
