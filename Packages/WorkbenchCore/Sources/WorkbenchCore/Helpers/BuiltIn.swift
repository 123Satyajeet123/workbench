/// The helpers that ship with Workbench. Each is data over the catalog; none has code of its own.
extension HelperSpec {
    /// Pip: the team's plans, done work and blockers from the team's WhatsApp group.
    public static let team = HelperSpec(
        task: "team.ledger", source: .whatsappChat,
        brief: """
            You keep a team ledger for the founder of a small company. For each team member, find what they plan to \
            do, what they did, and what blocks them. Use only what a message says. Chatter, greetings, links without \
            a status, and questions without an answer give no item. One message can give several items. A message can \
            be about another person: when the founder writes "Rahul, finish the API today", that is a plan of Rahul.
            """,
        fields: [
            Field("person", .member(of: "members"), meaning: "The team member the item is about."),
            Field(
                "kind", .choice(["plan", "done", "blocker"]),
                meaning:
                    "plan: to do, today or later. done: finished or progressed. blocker: stuck, waiting, needs help."),
            Field("text", .text(required: true), meaning: "One short English line in your words."),
            Field(
                "eta", .text(required: false),
                meaning:
                    "When the person said it would be done, in their words (\"kal tak\", \"by 6pm\"); empty when not said."
            ),
        ],
        citation: .one, view: .board(groupBy: "person", expected: "members"), title: "text", badges: ["eta"],
        tones: ["plan": .neutral, "done": .good, "blocker": .bad], itemsNoun: "entries",
        nudge: Nudge(field: "person", expected: "members", message: "No update today from"))

    /// The day timeline: the founder's screen sessions joined into blocks of work.
    public static let timeline = HelperSpec(
        task: "day.timeline", source: .screenSessions,
        brief: """
            You write the timeline of one work day of a founder. Join consecutive windows that serve one task into one \
            block, even across apps (for example a terminal, a browser tab with docs, and a chat about the same \
            feature). Start a new block when the task changes. Leave out windows that are breaks or that you cannot \
            tie to a task. Most blocks run 10 to 90 minutes; give a shorter block only for a distinct task.
            """,
        fields: [
            Field("task", .text(required: true), meaning: "What the founder did, in a few English words, verb first."),
            Field(
                "project", .text(required: false),
                meaning: "The product, client or area it belongs to, as named in the windows; empty when not clear."),
        ],
        citation: .range, view: .timeline, title: "task", badges: ["project"], tones: [:], itemsNoun: "blocks",
        nudge: nil)
}
