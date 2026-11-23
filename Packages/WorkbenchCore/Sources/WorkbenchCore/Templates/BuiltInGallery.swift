import Foundation

extension GalleryTemplate {
    public static let whatsAppReminders = GalleryTemplate(
        id: "whatsapp.reminders", name: "WhatsApp reminders", icon: "checklist",
        detail: "Keeps each person's plans, blockers and promises from your team chats, and reminds you what is open.",
        folder: FolderStart(name: "Team"), machine: .team,
        job: "Keep each person's plans, blockers and promises from the team's chats.",
        blocks: [.picker(.whatsapp), .facts(task: HelperSpec.team.task, view: "board")])

    public static let morningDigest = GalleryTemplate(
        id: "whatsapp.digest", name: "WhatsApp morning digest", icon: "sun.horizon",
        detail: "Each morning, the decisions, asks, news and problems of the groups you choose.",
        folder: FolderStart(name: "Morning digest"), machine: .morningDigest,
        job: "Tell me each morning what happened in these groups.",
        blocks: [.picker(.whatsapp), .facts(task: HelperSpec.morningDigest.task, view: "by kind")])

    public static let followUps = GalleryTemplate(
        id: "follow.ups", name: "Follow-up keeper", icon: "arrowshape.turn.up.left",
        detail: "Keeps what you owe people and what they owe you, from your chats, until it is done.",
        folder: FolderStart(name: "Follow-ups"), machine: .followUps,
        job: "Keep what I owe people and what they owe me.",
        blocks: [.picker(.whatsapp), .facts(task: HelperSpec.followUps.task, view: "open")])

    public static let dealIntake = GalleryTemplate(
        id: "deal.intake.gmail", name: "Deal intake from Gmail", icon: "tray.and.arrow.down",
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

    /// The gallery, in the founder's order.
    public static let all = [whatsAppReminders, morningDigest, followUps, dealIntake, claimCheck, companyResearch]
}
