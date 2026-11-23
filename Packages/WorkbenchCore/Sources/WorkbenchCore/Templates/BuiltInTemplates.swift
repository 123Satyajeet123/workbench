import Foundation

extension MachineTemplate {
    public static let team = MachineTemplate(
        spec: .team, name: "Pip", role: "Team facts",
        detail:
            "Reads the WhatsApp chats you choose and keeps each person's plans, done work, blockers, commitments, decisions and questions, by project."
    )
    public static let teamTelegram = MachineTemplate(
        spec: .teamTelegram, name: "Relay", role: "Team facts from Telegram",
        detail:
            "Reads one Telegram group whose members all agreed, and keeps each person's plans, done work, blockers, commitments, decisions and questions, by project."
    )
    public static let timeline = MachineTemplate(
        spec: .timeline, name: "Timeline", role: "Day timeline",
        detail: "Turns your screen sessions into blocks of work with the words they came from.")
    public static let pages = MachineTemplate(
        spec: .pages, name: "Scout", role: "Page reader",
        detail:
            "Reads the text of pages you saw on sites you name, such as your mail, and lists what needs your follow-up."
    )
    public static let dealIntake = MachineTemplate(
        spec: .dealIntake.setting(claimTypes: claimTypes), name: "Deal intake", role: "Deal intake",
        detail: "Reads your mail pages and lists each inbound startup, rated hot, warm or cold by your own criteria.")
    public static let dealsFromChats = MachineTemplate(
        spec: .dealIntake.reading(
            .whatsappChat, as: "vc.deals-chats",
            brief: """
                You read inbound deals for a venture investor from the WhatsApp chats they chose. For each startup \
                that someone pitches, asks the investor to meet or introduces, give one item with what the chat says \
                about it.
                """
        ).setting(claimTypes: claimTypes), name: "Deals from chats", role: "Deal intake from chats",
        detail: "Reads the WhatsApp chats you choose and lists each inbound startup, rated by your own criteria.")
    public static let outbound = MachineTemplate(
        spec: .outbound, name: "Outbound", role: "Startup search",
        detail:
            "Searches the web for startups that fit your criteria, reads each page, and lists the ones worth a look with the words that show why. You add one to Deals or turn it down."
    )
    public static let founderCheck = MachineTemplate(
        spec: .founderCheck, name: "Founder check", role: "Founder check",
        detail: "Reads founders' profile pages you opened and lists their roles, companies, exits and education.")
    public static let companySignals = MachineTemplate(
        spec: .companySignals, name: "Page signals", role: "Company signals from pages",
        detail:
            "Reads news and social pages you saw and lists funding, hires, launches and risks of companies you follow.")
    public static let newsSignals = MachineTemplate(
        spec: .newsSignals.setting(feeds: newsFeeds), name: "Signals", role: "News signals",
        detail:
            "Reads the news feeds in its list for your portfolio and the deals you passed on, and lists funding, layoffs, exits and other events, good and bad, with the words they came from."
    )
    public static let derailment = MachineTemplate(
        spec: .derailment, name: "Sentinel", role: "Off-track watch",
        detail:
            "Follows the open commitments, questions and decisions of Pip and tells you what is overdue, quiet, blocked or drifting."
    )
    public static let followUps = MachineTemplate(
        spec: .followUps, name: "Follow-ups", role: "Follow-up keeper",
        detail: "Reads the chats you choose and keeps what you owe people and what they owe you, until it is done.")
    public static let morningDigest = MachineTemplate(
        spec: .morningDigest, name: "Morning digest", role: "Group digest",
        detail: "Reads the WhatsApp groups you choose and gives you their decisions, asks, news and problems.")

    public static let all = [
        team, teamTelegram, timeline, pages, derailment, dealIntake, dealsFromChats, outbound, founderCheck,
        newsSignals, companySignals, followUps, morningDigest,
    ]
    /// The machines a store made before team templates starts with; the others are made on request or from Mochi's
    /// proposals.
    public static let seeded = [team, timeline]

    private static let newsFeeds = [
        NewsFeed(name: "Inc42", url: URL(string: "https://inc42.com/feed/")!, trusted: true),
        NewsFeed(name: "YourStory", url: URL(string: "https://yourstory.com/feed")!, trusted: true),
    ]

    private static let claimTypes = [
        ClaimType(
            id: "market_size", label: "market size", proof: "The named market report, with its figure and year."),
        ClaimType(
            id: "revenue_or_traction", label: "revenue or traction",
            proof: "The company's own public pages or a dated report of its figures."),
        ClaimType(
            id: "team_background", label: "team background",
            proof: "The company site, a profile page or press about the founders."),
        ClaimType(id: "funding", label: "funding", proof: "A dated news report or the investor's own page."),
        ClaimType(id: "customers", label: "customers", proof: "The customer's own page or a case study."),
        ClaimType(id: "other", label: "other", proof: "A page that states the same value for the same company."),
    ]
}

extension HelperSpec {
    /// The same machine over another source: its own task and brief.
    fileprivate func reading(_ source: Source, as task: String, brief: String) -> HelperSpec {
        var spec = self
        spec.source = source
        spec.task = task
        spec.brief = brief
        return spec
    }

    fileprivate func setting(feeds: [NewsFeed]? = nil, claimTypes: [ClaimType]? = nil) -> HelperSpec {
        var spec = self
        spec.feeds = feeds
        spec.claimTypes = claimTypes
        return spec
    }
}

extension ObjectTypes {
    public static let project = ObjectType(
        id: "project", noun: "project",
        fields: [FieldDef(id: "owner", label: "Owner", kind: .person), FieldDef(id: "due", label: "Due", kind: .date)],
        stages: [
            StageDef(id: "project.active", label: "Active", order: 1, meaning: .open),
            StageDef(
                id: "project.blocked", label: "Blocked", order: 2, meaning: .waiting, resumes: "project.active"),
            StageDef(id: "project.done", label: "Done", order: 3, meaning: .won),
            StageDef(id: "project.dropped", label: "Dropped", order: 4, meaning: .lost),
        ])
}

extension TeamTemplate {
    public static let fund = TeamTemplate(
        id: "fund", name: "Fund", purpose: "Find, screen and follow startups for an investment team.",
        objectTypes: [ObjectTypes.deal],
        machines: [
            TeamMachine(template: MachineTemplate.dealIntake.id, name: MachineTemplate.dealIntake.name),
            TeamMachine(template: MachineTemplate.outbound.id, name: MachineTemplate.outbound.name),
            TeamMachine(template: MachineTemplate.founderCheck.id, name: MachineTemplate.founderCheck.name),
            TeamMachine(template: MachineTemplate.newsSignals.id, name: MachineTemplate.newsSignals.name),
        ],
        optionalMachines: [
            TeamMachine(template: MachineTemplate.dealsFromChats.id, name: MachineTemplate.dealsFromChats.name)
        ])

    public static let startupTeam = TeamTemplate(
        id: "startup-team", name: "Startup team", purpose: "Keep a small team's plans, blockers and projects in view.",
        objectTypes: [ObjectTypes.project],
        machines: [
            TeamMachine(template: MachineTemplate.team.id, name: MachineTemplate.team.name),
            TeamMachine(template: MachineTemplate.derailment.id, name: MachineTemplate.derailment.name),
        ])

    public static let blank = TeamTemplate(
        id: "blank", name: "Blank", purpose: "A team with no machines and no kinds of work yet.", objectTypes: [],
        machines: [])

    public static let builtIn = [fund, startupTeam, blank]
}
