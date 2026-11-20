import Foundation

/// One of the founder's recurring jobs, as data. It names parts of a fixed catalog (a source, field kinds, a citation
/// mode, a view) and adds the brief: the job in plain words. Code derives the prompt rules, the output shape and every
/// check from these names, so a helper cannot skip consent or the quote check.
public struct HelperSpec: Codable, Sendable, Equatable {
    /// Where the evidence comes from. Each case is a reader in code, with its own consent kind.
    public enum Source: String, Codable, Sendable, CaseIterable {
        case whatsappChat = "whatsapp_chat"
        case screenSessions = "screen_sessions"
        /// The text of web pages the person saw, only on the sites the machine's owner named.
        case pageText = "page_text"
        /// Gmail threads the person opened inside the label they named, with the text of attached decks.
        case mail = "mail_threads"

        public var kind: SourceKind {
            switch self {
            case .whatsappChat: .whatsapp
            case .screenSessions: .screen
            case .pageText: .screenText
            case .mail: .mail
            }
        }

        /// What one line of this source is, for the founder.
        public var lineNoun: String {
            switch self {
            case .whatsappChat: "messages"
            case .screenSessions: "windows"
            case .pageText: "pages"
            case .mail: "messages"
            }
        }

        /// What the model is told about the lines it reads.
        var lines: String {
            switch self {
            case .whatsappChat:
                """
                one work day of a WhatsApp group. Each line is `[number] HH:mm sender: text`. People write in Hindi, \
                English and Hinglish.
                """
            case .screenSessions:
                """
                the windows the founder had in front, in order. Each line is `[number] HH:mm–HH:mm (minutes) app — \
                window title — address`; the address is a web page or a file and can be missing.
                """
            case .mail:
                """
                the mail threads the investor opened in their Deals label, in order. Each line is `[number] sender — \
                subject: the text`. A line of an attached deck also names the file and the page: `sender — subject — \
                file page 3: the text`. A thread shows one line for each message and each deck page.
                """
            case .pageText:
                """
                the text of web pages the founder had on screen, in order. Each line is `[number] HH:mm site — page \
                title: the text on screen`. The same page can appear again after a scroll, with new text.
                """
            }
        }
    }

    /// How an item points at its evidence: one line, a run of consecutive lines, or open facts of another machine
    /// (by handle) with the new lines that show it, if any.
    public enum Citation: String, Codable, Sendable {
        case one, range, facts
    }

    public struct Field: Codable, Sendable, Equatable {
        public enum Kind: Codable, Sendable, Equatable {
            /// Free text. A required field may not be empty.
            case text(required: Bool)
            case choice([String])
            /// A name from a context set the source gives, such as the group's members.
            case member(of: String)
            /// A short name that should stay the same over days, such as a project: the values this machine used
            /// before are shown under `set` for reuse, and a new one is allowed. Never empty.
            case label(of: String)
            /// A choice that code sets from the spec's criteria. The model is never asked for it.
            case computed([String])

            /// The values a choice or computed field may take; nil for the other kinds.
            public var fixedValues: [String]? {
                switch self {
                case .choice(let values), .computed(let values): values
                default: nil
                }
            }

            var isComputed: Bool { if case .computed = self { true } else { false } }
        }

        public var name: String
        /// What the field holds, as the model is told.
        public var meaning: String
        public var kind: Kind

        public init(_ name: String, _ kind: Kind, meaning: String) {
            self.name = name
            self.kind = kind
            self.meaning = meaning
        }
    }

    public enum Tone: String, Codable, Sendable {
        case good, attention, bad, neutral
    }

    public enum View: Codable, Sendable, Equatable {
        /// One section per value of a field, with every name of a context set shown, even with no item.
        case board(groupBy: String, expected: String)
        /// Items in time order with their span.
        case timeline
        /// One row per item, one column per field.
        case table
        /// One section per value of a choice field, in the choice's order: hot, warm, cold.
        case grouped(by: String)
        /// Open items first, one section per value of a field; closed items below with how they closed. Needs a
        /// lifecycle.
        case checklist(by: String)
    }

    /// The views this spec can fill, by name: a board needs a field that names a member, a timeline needs time spans,
    /// each choice or label field gives a view grouped by its values ("by rating", "by topic"), and with a lifecycle
    /// a checklist of what is still open, by project when a label field names one ("open by topic").
    public var views: [String: View] {
        var views: [String: View] = ["table": .table]
        if citation == .range { views["timeline"] = .timeline }
        for field in fields {
            switch field.kind {
            case .member(let set): views["board"] = .board(groupBy: field.name, expected: set)
            case .choice, .computed: views["by \(field.name)"] = .grouped(by: field.name)
            case .label:
                views["by \(field.name)"] = .grouped(by: field.name)
                if lifecycle != nil { views["open by \(field.name)"] = .checklist(by: field.name) }
            case .text: break
            }
        }
        if let lifecycle, !views.values.contains(where: { if case .checklist = $0 { true } else { false } }) {
            views["open"] = .checklist(by: lifecycle.field)
        }
        return views
    }

    /// Items of some values of a choice field stay open until a later line closes them: a commitment kept, a question
    /// answered, a decision reversed (research 32).
    public struct Lifecycle: Codable, Sendable, Equatable {
        public var field: String
        /// The values of `field` whose items stay open.
        public var open: [String]
        /// How a line may close one.
        public var outcomes: [String]
    }

    /// Once a work day, at the founder's time, name who in a context set has no item.
    public struct Nudge: Codable, Sendable, Equatable {
        public var field: String
        public var expected: String
        /// The words before the names: "No update today from".
        public var message: String
    }

    /// The names of the fields whose value is one of a fixed set.
    /// The lifecycle, or for a machine whose items only happened, one in which nothing stays open: its items are
    /// listed, none is open.
    public var lifecycleOrNone: Lifecycle {
        lifecycle ?? Lifecycle(field: choiceFields.first ?? "", open: [], outcomes: [])
    }

    public var choiceFields: [String] {
        fields.compactMap { field in
            if case .choice = field.kind { field.name } else { nil }
        }
    }

    /// Whether a machine of this spec needs another machine's open items to cite: it must be given `follows`.
    public var needsFollowed: Bool { citation == .facts }

    /// The run task name, stable across versions of the brief.
    public var task: String
    public var source: Source
    public var brief: String
    public var fields: [Field]
    public var citation: Citation
    public var view: View
    /// The field shown as an item's main line, and the fields shown beside it.
    public var title: String
    public var badges: [String]
    /// A choice value's tone, for the mark beside an item.
    public var tones: [String: Tone]
    /// What one item is called on screen: "entries", "blocks".
    public var itemsNoun: String
    public var nudge: Nudge?
    /// Nil for a machine whose items are only things that happened.
    public var lifecycle: Lifecycle? = nil
    /// The task of another machine whose open items this machine reads as handles. Used by a machine with no
    /// lifecycle of its own.
    public var follows: String? = nil
    /// How many items the founder marked on other training days the machine sees as examples; nil for none. It is
    /// part of the instructions, so changing it makes a new version that earns trust again (research 20 §9.2).
    public var examples: Int? = nil
    /// The investor's thesis: rules the model judges one by one, combined by code into the spec's computed field. Any
    /// change to it is a new prompt version.
    public var criteria: Criteria? = nil
    /// The model this machine reads with, as a model choice id such as "claude sonnet"; nil uses the founder's choice.
    /// Trust is counted per model, so a new runner earns trust again (research 20 §7.1).
    public var runner: String? = nil
}

extension HelperSpec {
    /// The parts of a newer built-in this machine lacks, in plain words, or nil when its design is current. The brief
    /// alone does not count: the founder may have improved it, and a new brief is offered with a new design only.
    public func update(toward builtIn: HelperSpec) -> [String]? {
        let mine = Set(fields.map(\.name))
        var changes = builtIn.fields.map(\.name).filter { !mine.contains($0) }.map { "adds \($0)" }
        changes += fields.map(\.name).filter { name in !builtIn.fields.contains { $0.name == name } }.map {
            "drops \($0)"
        }
        let changedKinds = builtIn.fields.filter { field in
            fields.contains { $0.name == field.name && $0.kind != field.kind }
        }
        changes += changedKinds.map { "changes \($0.name)" }
        if criteria == nil, builtIn.criteria != nil { changes.append("adds criteria") }
        if lifecycle == nil, builtIn.lifecycle != nil { changes.append("lets facts open and close") }
        if lifecycle != nil, builtIn.lifecycle == nil { changes.append("stops opening and closing facts") }
        if lifecycle != nil, let next = builtIn.lifecycle, lifecycle != next {
            changes.append("changes how facts close")
        }
        if source != builtIn.source || citation != builtIn.citation { changes.append("reads and cites differently") }
        if nudge != builtIn.nudge || tones != builtIn.tones { changes.append("changes its alerts") }
        return changes.isEmpty ? nil : changes
    }
}
