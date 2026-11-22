import Foundation

public struct HelperSpec: Codable, Sendable, Equatable {
    public enum Source: String, Codable, Sendable, CaseIterable {
        case whatsappChat = "whatsapp_chat"
        case screenSessions = "screen_sessions"
        case pageText = "page_text"
        case mail = "mail_threads"

        public var kind: SourceKind {
            switch self {
            case .whatsappChat: .whatsapp
            case .screenSessions: .screen
            case .pageText: .screenText
            case .mail: .mail
            }
        }

        public var lineNoun: String {
            switch self {
            case .whatsappChat: "messages"
            case .screenSessions: "windows"
            case .pageText: "pages"
            case .mail: "messages"
            }
        }

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

    public enum Citation: String, Codable, Sendable {
        case one, range, facts
    }

    public struct Field: Codable, Sendable, Equatable {
        public enum Kind: Codable, Sendable, Equatable {
            case text(required: Bool)
            case choice([String])
            case member(of: String)
            case label(of: String)
            case computed([String])

            public var fixedValues: [String]? {
                switch self {
                case .choice(let values), .computed(let values): values
                default: nil
                }
            }

            var isComputed: Bool { if case .computed = self { true } else { false } }
        }

        public var name: String
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
        case board(groupBy: String, expected: String)
        case timeline
        case table
        case grouped(by: String)
        case checklist(by: String)
    }

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

    public struct Lifecycle: Codable, Sendable, Equatable {
        public var field: String
        public var open: [String]
        public var outcomes: [String]
    }

    public struct Nudge: Codable, Sendable, Equatable {
        public var field: String
        public var expected: String
        public var message: String
    }

    public var lifecycleOrNone: Lifecycle {
        lifecycle ?? Lifecycle(field: choiceFields.first ?? "", open: [], outcomes: [])
    }

    public var choiceFields: [String] {
        fields.compactMap { field in
            if case .choice = field.kind { field.name } else { nil }
        }
    }

    public var needsFollowed: Bool { citation == .facts }

    public var task: String
    public var source: Source
    public var brief: String
    public var fields: [Field]
    public var citation: Citation
    public var view: View
    public var title: String
    public var badges: [String]
    public var tones: [String: Tone]
    public var itemsNoun: String
    public var nudge: Nudge?
    public var lifecycle: Lifecycle? = nil
    public var follows: String? = nil
    public var examples: Int? = nil
    public var criteria: Criteria? = nil
    public var runner: String? = nil
}

extension HelperSpec {
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
