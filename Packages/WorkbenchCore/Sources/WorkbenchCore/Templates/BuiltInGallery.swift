import Foundation

extension GalleryTemplate {
    public static let whatsAppReminders = GalleryTemplate(
        id: MachineTemplate.team.id, name: "WhatsApp reminders", icon: "checklist",
        detail: "Keeps each person's plans, blockers and promises from your team chats, and reminds you what is open.",
        folder: FolderStart(name: "Team"), machine: .team,
        job: "Keep each person's plans, blockers and promises from the team's chats.",
        blocks: [.picker(.whatsapp), .facts(task: HelperSpec.team.task, view: "board")])

    public static let morningDigest = GalleryTemplate(
        id: MachineTemplate.morningDigest.id, name: "WhatsApp morning digest", icon: "sun.horizon",
        detail: "Each morning, the decisions, asks, news and problems of the groups you choose.",
        folder: FolderStart(name: "Morning digest"), machine: .morningDigest,
        job: "Tell me each morning what happened in these groups.",
        blocks: [.picker(.whatsapp), .facts(task: HelperSpec.morningDigest.task, view: "by kind")])

    public static let followUps = GalleryTemplate(
        id: MachineTemplate.followUps.id, name: "Follow-up keeper", icon: "arrowshape.turn.up.left",
        detail: "Keeps what you owe people and what they owe you, from your chats, until it is done.",
        folder: FolderStart(name: "Follow-ups"), machine: .followUps,
        job: "Keep what I owe people and what they owe me.",
        blocks: [.picker(.whatsapp), .facts(task: HelperSpec.followUps.task, view: "open")])

    public static let dealIntake = GalleryTemplate(
        id: MachineTemplate.dealIntake.id, name: "Deal intake from Gmail", icon: "tray.and.arrow.down",
        detail: "Lists each inbound startup from a Gmail label, rated hot, warm or cold by your own rules.",
        folder: FolderStart(name: "Deals", holds: ObjectTypes.deal.id), machine: .dealIntake,
        job: "List each startup that reaches me by mail, rated by my rules.",
        blocks: [.picker(.mail), .input(.criteria), .facts(task: HelperSpec.dealIntake.task, view: "by rating")])

    public static let claimCheck = GalleryTemplate(
        id: "deal.claims", name: "Check a deal's claims", icon: "checkmark.seal",
        detail: "Add a deck or a document, and check its claims against public sources, each with its page.",
        folder: FolderStart(name: "Deals", holds: ObjectTypes.deal.id), machine: nil,
        job: "Check what a deal claims against public sources.",
        blocks: [.picker(.dropped), .facts(task: ClaimExtractor.task, view: "table")])

    public static let companyResearch = GalleryTemplate(
        id: "company.research", name: "Research a company", icon: "magnifyingglass",
        detail: "Ask about a company, and keep what is found on the web, each with its source.",
        folder: FolderStart(name: "Research"), machine: nil,
        job: "Look up a company on the web and keep what is found, with its source.",
        blocks: [.heading("Companies")], needs: [.taskRunner])

    public static let dealsFromChats = GalleryTemplate(
        id: MachineTemplate.dealsFromChats.id, name: "Deals from chats", icon: "bubble.left.and.text.bubble.right",
        detail: "Lists each startup that reaches you in the WhatsApp chats you choose, rated by your own rules.",
        folder: FolderStart(name: "Deals", holds: ObjectTypes.deal.id), machine: .dealsFromChats,
        job: "List each startup that reaches me in these chats, rated by my rules.",
        blocks: [
            .picker(.whatsapp), .input(.criteria), .facts(task: MachineTemplate.dealsFromChats.id, view: "by rating"),
        ])

    public static let outbound = GalleryTemplate(
        id: MachineTemplate.outbound.id, name: "Find startups", icon: "scope",
        detail: "Searches the web for startups that fit your rules, and lists each one with the page it came from.",
        folder: FolderStart(name: "Deals", holds: ObjectTypes.deal.id), machine: .outbound,
        job: "Find startups on the web that fit my rules.",
        blocks: [.input(.criteria), .facts(task: MachineTemplate.outbound.id, view: "table")])

    public static let founderCheck = GalleryTemplate(
        id: MachineTemplate.founderCheck.id, name: "Founder check", icon: "person.text.rectangle",
        detail: "Reads the founder pages you open on the sites you choose, and keeps what they say about the founders.",
        folder: FolderStart(name: "Deals", holds: ObjectTypes.deal.id), machine: .founderCheck,
        job: "Keep what the pages I read say about each founder.",
        blocks: [.picker(.screenText), .facts(task: MachineTemplate.founderCheck.id, view: "table")])

    public static let newsSignals = GalleryTemplate(
        id: MachineTemplate.newsSignals.id, name: "Company news", icon: "newspaper",
        detail: "Reads the news feeds you choose for the companies you follow.",
        folder: FolderStart(name: "Watchlist"), machine: .newsSignals,
        job: "Tell me what the news says about the companies I follow.",
        blocks: [.input(.feeds), .facts(task: MachineTemplate.newsSignals.id, view: "table")])

    public static let offTrack = GalleryTemplate(
        id: MachineTemplate.derailment.id, name: "Off-track watch", icon: "exclamationmark.triangle",
        detail: MachineTemplate.derailment.detail,
        folder: FolderStart(name: "Team"), machine: .derailment,
        job: "Tell me what in the team's open work is overdue, quiet, blocked or drifting.",
        blocks: [.facts(task: MachineTemplate.derailment.id, view: "table")])

    /// The first row of the gallery, in the founder's order.
    public static let featured = [whatsAppReminders, morningDigest, followUps, dealIntake, claimCheck, companyResearch]

    /// Every gallery template: the featured ones, then the ones the team templates use.
    public static let all = featured + [dealsFromChats, outbound, founderCheck, newsSignals, offTrack]
}
