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
extension HelperSpec.Field {
    /// How a line says when something is due, in English, Hindi or Hinglish, read as a record.
    static let dueWords = """
        When it is due, from the words of the line, as a record: you never write a date. Read the tense \
        of the sentence for the direction: "kal" and "parson" are the days before today in a sentence \
        about the past ("kal deck bheja") and the days after today in one about a promise or a plan \
        ("kal tak bhej dunga"). "kal tak" is one day from the line, "parson" two, "narson" three; \
        "aaj shaam" is today, evening; EOD and COB are today, evening. "kal subah 10 baje" is one day \
        from the line, morning, hour 10; "5 baje" alone has no meridiem. "2 ghante mein" is 120 minutes. \
        "30 tareekh tak" is day 30 of this month; "agle mahine ki 15" is day 15, month next; "15 Dec" is \
        day 15, month 12. "mahine ke end tak" is precision month, this; "agle hafte" is precision week, \
        next; "is hafte" or EOW is week, this. A range such as "Monday se Wednesday" is due at its end. \
        When the line was sent late at night, after midnight and before the writer likely slept, and it \
        says "kal", "aaj" or "parson", two days fit: set ambiguous to true. Set ambiguous to true too \
        when "next Monday" or "agle Monday" can mean two Mondays. A quarter, a repeat ("har Monday"), a \
        festival or working days have no field: set precision none, and give the words. When the line \
        says no time, set precision none, direction unclear and words empty.
        """
}

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
            Field("when", .time, meaning: Field.dueWords),
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
        badges: ["project"],
        tones: [
            "plan": .neutral, "done": .good, "blocker": .bad, "commitment": .neutral, "decision": .neutral,
            "question": .attention, "status": .neutral,
        ],
        itemsNoun: "entries", nudge: Nudge(field: "person", expected: "members", message: "No update today from"),
        lifecycle: Lifecycle(
            field: "kind", open: ["plan", "blocker", "commitment", "question", "decision"],
            outcomes: ["kept", "answered", "resolved", "reversed", "dropped"], owner: "person",
            doneOutcomes: ["blocker": "resolved"]))

    public static let teamTelegram: HelperSpec = {
        var spec = team
        spec.task = "team.telegram"
        spec.source = .telegramChat
        return spec
    }()

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
            - overdue: a plan or commitment is past its due day (due=), or its time has clearly passed, and no new line shows it done;
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

    /// What the person and the people they talk to owe each other, from the chats the person chose. An item stays
    /// open until a later line keeps, answers or drops it.
    public static let followUps = HelperSpec(
        task: "follow.ups", source: .whatsappChat,
        brief: """
            You keep what the person and the people they talk to owe each other, from the chats they chose. Give one \
            item for each line where someone asks the person for something, promises the person something, or the \
            person promises something to someone. Use only what a message says. Greetings, thanks and chatter give no \
            item. Write each item in plain English even when the message is in Hindi or Hinglish.
            """,
        fields: [
            Field(
                "who", .text(required: true), meaning: "The other person: who asks, who promises, or who is promised."),
            Field(
                "owes", .choice(["you", "them"]),
                meaning: "you: the person owes it (they were asked, or they promised). them: the other person owes it."),
            Field(
                "kind", .choice(["ask", "promise"]),
                meaning: "ask: someone asks for something. promise: someone says they will do something."),
            Field("text", .text(required: true), meaning: "What is owed, in one short English line."),
            Field("when", .time, meaning: Field.dueWords),
        ],
        citation: .one, view: .checklist(by: "owes"), title: "text", badges: ["who"],
        tones: ["ask": .attention, "promise": .neutral], itemsNoun: "follow-ups", nudge: nil,
        lifecycle: Lifecycle(
            field: "kind", open: ["ask", "promise"], outcomes: ["kept", "answered", "dropped"], owner: "who"))

    /// What happened in the groups the person chose, for the next morning: decisions, asks of the person, news,
    /// plans and problems.
    public static let morningDigest = HelperSpec(
        task: "morning.digest", source: .whatsappChat,
        brief: """
            You write the morning digest of the WhatsApp groups the person chose. Give one item for each thing the \
            person would want to know the next morning: a decision, a request of the person, news, a plan or a \
            problem. Use only what a message says. Greetings, thanks, chatter and forwards with no news give no item. \
            Write each item in plain English even when the message is in Hindi or Hinglish.
            """,
        fields: [
            Field(
                "kind", .choice(["asks you", "decision", "news", "plan", "problem"]),
                meaning: "asks you: a request of the person or a wait on them. The others as named."),
            Field("text", .text(required: true), meaning: "The thing, in one short English line."),
            Field("who", .text(required: false), meaning: "Who said it or who it is about; empty when not said."),
        ],
        citation: .one, view: .grouped(by: "kind"), title: "text", badges: ["who"],
        tones: ["asks you": .attention, "problem": .bad], itemsNoun: "points", nudge: nil)
}

extension HelperSpec.Attention {
    /// The words the built-in machines write and Today reads: the `asks` value of a fact that waits on the founder, and
    /// the `severity` values of a finding that needs action now or soon.
    public static let builtIn = HelperSpec.Attention(
        asksMe: Mark("asks", "founder"), act: Mark("severity", "act"), watch: Mark("severity", "watch"))
}
