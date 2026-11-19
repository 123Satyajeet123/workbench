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

        public var kind: SourceKind {
            switch self {
            case .whatsappChat: .whatsapp
            case .screenSessions: .screen
            case .pageText: .screenText
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
            case .pageText:
                """
                the text of web pages the founder had on screen, in order. Each line is `[number] HH:mm site — page \
                title: the text on screen`. The same page can appear again after a scroll, with new text.
                """
            }
        }
    }

    /// How an item points at its evidence: one line, or a run of consecutive lines.
    public enum Citation: String, Codable, Sendable {
        case one, range
    }

    public struct Field: Codable, Sendable, Equatable {
        public enum Kind: Codable, Sendable, Equatable {
            /// Free text. A required field may not be empty.
            case text(required: Bool)
            case choice([String])
            /// A name from a context set the source gives, such as the group's members.
            case member(of: String)
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
    }

    /// The views this spec can fill, by name: a board needs a field that names a member, a timeline needs time spans.
    public var views: [String: View] {
        var views: [String: View] = ["table": .table]
        if citation == .range { views["timeline"] = .timeline }
        for field in fields {
            if case .member(let set) = field.kind { views["board"] = .board(groupBy: field.name, expected: set) }
        }
        return views
    }

    /// Once a work day, at the founder's time, name who in a context set has no item.
    public struct Nudge: Codable, Sendable, Equatable {
        public var field: String
        public var expected: String
        /// The words before the names: "No update today from".
        public var message: String
    }

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
    /// How many items the founder marked on other training days the machine sees as examples; nil for none. It is
    /// part of the instructions, so changing it makes a new version that earns trust again (research 20 §9.2).
    public var examples: Int? = nil
    /// The model this machine reads with, as a model choice id such as "claude sonnet"; nil uses the founder's choice.
    /// Trust is counted per model, so a new runner earns trust again (research 20 §7.1).
    public var runner: String? = nil
}
