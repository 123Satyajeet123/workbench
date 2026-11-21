extension Criteria {
    /// The rules a new deal machine starts with: they only mirror the old placeholder, and the investor edits them
    /// into their own thesis. A new Outbound machine copies the criteria of the Deal intake machine when one exists.
    public static let starter = Criteria(rules: [
        Rule(
            id: "r_stage", role: .must,
            test: .text(TextTest(says: "The startup raises a pre-seed, seed or Series A round.", wants: true))),
        Rule(
            id: "r_traction", role: .plus,
            test: .text(TextTest(says: "The startup shows revenue or strong traction.", wants: true))),
    ])
}

/// The helpers that ship with Workbench. Each is data over the catalog; none has code of its own.
extension HelperSpec {
    /// Pip, the fact machine: what each person plans, did and is stuck on, and what is decided or asked, by project,
    /// from the chats the founder chose. Open facts stay open until a later line closes them (research 32).
    public static let team = HelperSpec(
        task: "team.ledger", source: .whatsappChat,
        brief: """
            You keep the facts of a founder's company from its work chats: one group or several. Give one item for \
            each fact a message states, with the person it is about and the project it belongs to. Use only what a \
            message says. Chatter, greetings, thanks, links without a status, and a question that the same lines \
            answer give no item. One message can give several items. A message can be about another person: when the \
            founder writes "Rahul, finish the API today", that is a plan of Rahul. Write each fact in plain English \
            even when the message is in Hindi or Hinglish. A person's plans, done work and blockers make the team \
            ledger; a project's commitments, decisions, questions and status make its record. One fact has one item.
            """,
        fields: [
            Field(
                "person", .member(of: "members"),
                meaning: "The team member the fact is about, or who owes it."),
            Field(
                "project", .label(of: "topics"),
                meaning: "The project or topic, in two to four words. Use \"General\" when it belongs to none."),
            Field(
                "kind",
                .choice(["plan", "done", "blocker", "commitment", "decision", "question", "status"]),
                meaning:
                    "plan: to do, today or later. done: finished or progressed. blocker: stuck, waiting, needs help. commitment: someone promises a result to another person. decision: something agreed or chosen. question: asked and not answered in these lines. status: where a piece of work stands now."
            ),
            Field("text", .text(required: true), meaning: "One short English line in your words."),
            Field(
                "eta", .text(required: false),
                meaning:
                    "The date it is due, as YYYY-MM-DD, worked out from the work day and the person's words (\"kal tak\" is the next day, \"Fri\" the coming Friday); empty when no time was said, never guessed."
            ),
            Field(
                "stance", .choice(["said", "reported"]),
                meaning: "said: written by the person it is about. reported: written by someone else."),
            Field(
                "asks", .choice(["founder", "team"]),
                meaning:
                    "founder: the fact asks the founder for something or waits on the founder: a decision, an answer, an approval, a reply. team: every other fact."
            ),
        ],
        citation: .one, view: .board(groupBy: "person", expected: "members"), title: "text",
        badges: ["project", "eta"],
        tones: [
            "plan": .neutral, "done": .good, "blocker": .bad, "commitment": .neutral, "decision": .neutral,
            "question": .attention, "status": .neutral,
        ],
        itemsNoun: "entries", nudge: Nudge(field: "person", expected: "members", message: "No update today from"),
        lifecycle: Lifecycle(
            field: "kind", open: ["plan", "blocker", "commitment", "question", "decision"],
            outcomes: ["kept", "answered", "resolved", "reversed", "dropped"]))

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

    /// VC pack: inbound deals from the investor's mail pages, judged against the investor's own criteria. The model
    /// judges each rule with a quote; code makes the hot, warm or cold call from the rule results. The starter rules
    /// only mirror the old placeholder: the investor edits them into their own thesis.
    public static let dealIntake = HelperSpec(
        task: "vc.deals", source: .mail,
        brief: """
            You read inbound deals for a venture investor from the mail threads they opened in their Deals label, and \
            from the decks attached to them. For each startup that pitches, asks for a meeting or is introduced, give \
            one item with what the mail or the deck says about it.
            """,
        fields: [
            Field("company", .text(required: true), meaning: "The startup's name."),
            Field("sector", .text(required: false), meaning: "What it does, in a few words; empty when not said."),
            Field(
                "stage", .choice(["pre-seed", "seed", "series A", "later", "unknown"]),
                meaning: "The round it raises, as the mail says; unknown when not said."),
            Field("from", .text(required: false), meaning: "Who wrote or introduced it; empty when not said."),
            Field(
                "rating", .computed(["hot", "warm", "cold"]),
                meaning: "Hot, warm or cold, from the criteria, by the table."),
        ],
        citation: .one, view: .grouped(by: "rating"), title: "company", badges: ["rating", "stage"],
        tones: ["hot": .good, "warm": .neutral, "cold": .bad], itemsNoun: "deals", nudge: nil,
        criteria: .starter)

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

    /// The derailment watch: what is going off track, from the open facts of the first machine with a lifecycle (Pip)
    /// and the new lines of a chat (research 31). Its `follows` is set when a person makes the machine.
    public static let derailment = HelperSpec(
        task: "work.derailment", source: .whatsappChat,
        brief: """
            You watch a founder's work for what is going off track. You get the facts still open in the founder's work \
            record (plans, blockers, commitments, questions, decisions), each with a handle, and the new lines of a work chat. Today's \
            date is the work day you are given. Decide from the facts and the lines what is off track. A finding is \
            one of:
            - overdue: a plan or commitment is past its eta, or its time has clearly passed, and no new line shows it done;
            - quiet: a thread or a person that should be moving has gone silent for longer than is usual for them;
            - blocked: work waits on something or someone and nothing moves it;
            - drift: the lines show work moving away from what the founder said matters;
            - contradicted: a new line says the opposite of an open fact.
            For each finding, cite the open facts it is about by handle, and the new lines that show it, if any. A \
            finding on silence has no new line: say in the reason what you could not see, because you see only the \
            lines you got, not other chats or the screen. When a new line says a commitment is done, it is not \
            overdue. A fact reported by someone else is weaker than one the person said: give it a lower severity. \
            Severity: act = the founder must act today; watch = worth a look soon; info = for awareness. Next is the \
            one concrete step the founder can take. With no next step, give no finding. Reason is why it is off track, \
            in one or two plain English sentences. When nothing is off track, give no item.
            """,
        fields: [
            Field(
                "kind", .choice(["overdue", "quiet", "blocked", "drift", "contradicted"]),
                meaning: "What kind of finding it is."),
            Field("project", .label(of: "topics"), meaning: "The project or topic it is about, in two to four words."),
            Field("severity", .choice(["act", "watch", "info"]), meaning: "How urgent it is for the founder."),
            Field("next", .text(required: true), meaning: "The one step the founder can take, in a few English words."),
            Field("reason", .text(required: true), meaning: "Why it is off track, in one or two English sentences."),
        ],
        citation: .facts, view: .grouped(by: "severity"), title: "next", badges: ["project", "kind"],
        tones: ["act": .bad, "watch": .attention, "info": .neutral], itemsNoun: "findings", nudge: nil)
}
