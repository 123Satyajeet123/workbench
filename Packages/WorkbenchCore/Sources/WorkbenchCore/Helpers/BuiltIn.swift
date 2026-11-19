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

    /// A page reader: what matters in the pages the founder saw on sites they name. Its brief says what to list.
    public static let pages = HelperSpec(
        task: "page.reader", source: .pageText,
        brief: """
            You read the web pages a founder saw on the sites they chose, such as their mail, LinkedIn or X. List each \
            thing that needs the founder's attention or follow-up: a request, an introduction, a pitch, a deadline. \
            Use only what a page says. Menus, ads and repeated page furniture give no item.
            """,
        fields: [
            Field("title", .text(required: true), meaning: "The thing, in a few English words."),
            Field(
                "who", .text(required: false),
                meaning: "The person or company it is about or from; empty when not said."),
            Field(
                "next", .text(required: false),
                meaning: "What the founder could do next, in a few words; empty when nothing."),
        ],
        citation: .one, view: .table, title: "title", badges: ["who"], tones: [:], itemsNoun: "items", nudge: nil)

    /// VC pack: inbound deals from the investor's mail pages, rated against the investor's own criteria.
    public static let dealIntake = HelperSpec(
        task: "vc.deals", source: .pageText,
        brief: """
            You triage inbound deals for a venture investor from the mail pages they read. For each startup that \
            pitches, asks for a meeting or is introduced, give one item. Rate it against the investor's criteria \
            below and say which criterion decided the rating. Criteria (the investor edits these): hot = fits our \
            sectors and stage, and shows revenue or strong traction; warm = fits sector or stage, but not both, or \
            traction is unclear; cold = outside our sectors or stage.
            """,
        fields: [
            Field("company", .text(required: true), meaning: "The startup's name."),
            Field("sector", .text(required: false), meaning: "What it does, in a few words; empty when not said."),
            Field(
                "stage", .choice(["pre-seed", "seed", "series A", "later", "unknown"]),
                meaning: "The round it raises, as the mail says; unknown when not said."),
            Field("from", .text(required: false), meaning: "Who wrote or introduced it; empty when not said."),
            Field("rating", .choice(["hot", "warm", "cold"]), meaning: "The rating under the criteria."),
            Field("why", .text(required: true), meaning: "The criterion that decided the rating, in a few words."),
        ],
        citation: .one, view: .table, title: "company", badges: ["rating", "stage"],
        tones: ["hot": .good, "warm": .neutral, "cold": .bad], itemsNoun: "deals", nudge: nil)

    /// VC pack: what a founder's profile page says, to check against what the pitch claims.
    public static let founderCheck = HelperSpec(
        task: "vc.founders", source: .pageText,
        brief: """
            You read the profile pages of founders a venture investor looked at. For each founder, list the facts the \
            page states that matter for an investment: past roles, companies founded, exits, education. One item per \
            fact. Use only what the page says; never guess.
            """,
        fields: [
            Field("person", .text(required: true), meaning: "The founder's name."),
            Field("fact", .text(required: true), meaning: "One fact from the profile, in a few English words."),
            Field("kind", .choice(["role", "founded", "exit", "education", "other"]), meaning: "What kind of fact."),
        ],
        citation: .one, view: .table, title: "fact", badges: ["person", "kind"], tones: [:], itemsNoun: "facts",
        nudge: nil)

    /// VC pack: news about portfolio and passed companies from the pages the investor reads.
    public static let companySignals = HelperSpec(
        task: "vc.signals", source: .pageText,
        brief: """
            You watch for news about companies a venture investor follows: their portfolio and deals they passed on. \
            From the news and social pages they read, list each signal about a named company: a funding round, a key \
            hire or departure, a launch, a risk, or press. One item per signal.
            """,
        fields: [
            Field("company", .text(required: true), meaning: "The company the signal is about."),
            Field(
                "signal", .choice(["funding", "hire", "departure", "launch", "risk", "press"]), meaning: "Its kind."),
            Field("text", .text(required: true), meaning: "The signal in one short English line."),
        ],
        citation: .one, view: .table, title: "text", badges: ["company", "signal"],
        tones: ["funding": .good, "launch": .good, "risk": .bad, "departure": .bad], itemsNoun: "signals", nudge: nil)

    /// The work context: commitments, decisions, open questions, status and roles from the founder's work chats, each
    /// with its topic, so a project's state builds up across days and chats.
    public static let context = HelperSpec(
        task: "work.context", source: .whatsappChat,
        brief: """
            You keep a founder's work context from their work chats: groups and direct chats at their company. From \
            each message that states one, give an item:
            - commitment: someone says they or another person will do something;
            - decision: something agreed or chosen;
            - question: asked and not answered in these lines;
            - status: where a piece of work stands now;
            - role: who is responsible for what.
            Use only what a message says. Chatter, greetings, thanks and bare links give no item. Write the fact in \
            plain English even when the message is in Hindi or Hinglish.
            """,
        fields: [
            Field(
                "kind", .choice(["commitment", "decision", "question", "status", "role"]),
                meaning: "What kind of fact it is."),
            Field("text", .text(required: true), meaning: "The fact in one short English line."),
            Field(
                "who", .text(required: false),
                meaning: "The person it is about or who owes it, as named in the chat; empty when no one is."),
            Field("topic", .label(of: "topics"), meaning: "The project or topic, in two to four words."),
            Field(
                "due", .text(required: false),
                meaning:
                    "When it is due, as an absolute date worked out from the message date (\"Fri 21 Nov\"); empty when not said, never guessed."
            ),
            Field(
                "stance", .choice(["said", "reported"]),
                meaning: "said: written by the person it is about. reported: written by someone else."),
        ],
        citation: .one, view: .checklist(by: "topic"), title: "text", badges: ["kind", "who", "due"], tones: [:],
        itemsNoun: "facts", nudge: nil,
        lifecycle: Lifecycle(
            field: "kind", open: ["commitment", "question", "decision"],
            outcomes: ["kept", "answered", "reversed", "dropped"]))
}
