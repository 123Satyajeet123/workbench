import WorkbenchCore

struct MachineTemplate: Identifiable, Hashable {
    let spec: HelperSpec
    let name: String
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
    static let founderCheck = MachineTemplate(
        spec: .founderCheck, name: "Founder check", role: "Founder check",
        detail: "Reads founders' profile pages you opened and lists their roles, companies, exits and education.")
    static let companySignals = MachineTemplate(
        spec: .companySignals, name: "Signals", role: "Company signals",
        detail: "Reads news and social pages and lists funding, hires, launches and risks of companies you follow.")
    static let derailment = MachineTemplate(
        spec: .derailment, name: "Sentinel", role: "Off-track watch",
        detail:
            "Follows the open commitments, questions and decisions of Pip and tells you what is overdue, quiet, blocked or drifting."
    )
    static let all = [team, timeline, pages, derailment, dealIntake, founderCheck, companySignals]
    static let seeded = [team, timeline]

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    static func of(_ machine: Machine) -> MachineTemplate? { all.first { $0.spec.task == machine.template } }
}
