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
        spec: .team, name: "Pip", role: "Team updates",
        detail: "Reads one WhatsApp group you choose and lists each person's plans, done work and blockers.")
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
    static let founderCheck = MachineTemplate(
        spec: .founderCheck, name: "Founder check", role: "Founder check",
        detail: "Reads founders' profile pages you opened and lists their roles, companies, exits and education.")
    static let companySignals = MachineTemplate(
        spec: .companySignals, name: "Signals", role: "Company signals",
        detail: "Reads news and social pages and lists funding, hires, launches and risks of companies you follow.")
    static let workContext = MachineTemplate(
        spec: .context, name: "Atlas", role: "Work context",
        detail:
            "Reads the work chats you choose and keeps commitments, decisions, open questions, status and roles, by project."
    )
    static let all = [team, timeline, pages, workContext, dealIntake, founderCheck, companySignals]
    /// The machines every store starts with; the others are made on request or from Mochi's proposals.
    static let seeded = [team, timeline]

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    static func of(_ machine: Machine) -> MachineTemplate? { all.first { $0.spec.task == machine.template } }
}
