import Foundation

/// A block of a machine as the editor draws it: the stored block with everything it shows already worked out by code.
/// The editor adds, counts and fetches nothing.
enum MachineView: Equatable, Sendable {
    case heading(text: String)
    case text(text: String, cites: [CiteChip])
    case facts(FactsRendering)
    case grid(GridRendering)
    case picker(PickerRendering)
    case status(StatusRendering)
    case line(LineRendering)
    case settings(SettingsRendering)
    case erased(note: String)
}

struct CiteChip: Codable, Equatable, Sendable {
    var ref: String
    var label: String
    var opens: Bool
}

struct FactsRendering: Codable, Equatable, Sendable {
    var title: String
    /// What the machine says of a heading it did not understand; empty otherwise.
    var note: String = ""
    var layout: String
    var countText: String
    /// How many facts ask the person, in words; empty when none does.
    var needsText: String
    /// How many facts of a section show before the rest fold; 0 shows them all.
    var limit: Int
    /// What the person may switch the view to; every choice in it is one the gate allows.
    var viewBar: ViewBar
    var columns: [String]
    /// The values the sections are counted by, in the order every section's tally follows; empty for an unfolded view.
    var tallyColumns: [String]
    var sections: [Section]

    struct Section: Codable, Equatable, Sendable {
        var name: String
        var countText: String
        var count: Int
        var needs: Int
        var summary: Summary?
        var tally: [Tally]
        var latest: String
        var latestDay: String
        var rows: [Row]
    }

    struct ViewBar: Codable, Equatable, Sendable {
        var form: String
        var forms: [String]
        var groupBy: String
        var groups: [String]
    }

    struct Summary: Codable, Equatable, Sendable {
        var text: String
        var cites: [CiteChip]
    }

    struct Tally: Codable, Equatable, Sendable {
        var value: String
        var count: Int
        var tone: String
    }

    struct Tag: Codable, Equatable, Sendable {
        var text: String
        var tone: String
    }

    struct Row: Codable, Equatable, Sendable {
        var fact: Int64
        /// What the fact is about, when the sections do not already say it: a member, else the machine's title.
        var subject: String
        var words: String
        var cells: [String]
        var needs: [Tag]
        var tags: [Tag]
        var due: String
        var state: String
        var marks: [FactMark]
    }
}

struct GridRendering: Codable, Equatable, Sendable {
    var title: String
    var columns: [String]
    var rows: [[Cell]]
    var cites: [CiteChip]

    struct Cell: Codable, Equatable, Sendable {
        var text: String
        var kind: String
        var source: String
    }
}

struct PickerRendering: Codable, Equatable, Sendable {
    var source: String
    var title: String
    var note: String
    var available: Bool
}

/// What the machine says of itself, worked out by code: what stops the page, what it reads, what it does now, and its
/// latest reading as lines.
struct StatusRendering: Codable, Equatable, Sendable {
    var notices: [String]
    var sentence: String
    var journal: [String]
    /// The phrase of the sentence that starts a reading now; nil when none is offered.
    var act: ActionLink?
}

/// A phrase of a line that the person may click, and what Swift does when they do.
struct ActionLink: Codable, Equatable, Sendable {
    var name: OpenTarget.Action
    var label: String
}

/// The settings of a machine, each as one sentence whose values are chips.
struct SettingsRendering: Codable, Equatable, Sendable {
    var sentences: [Sentence]

    struct Sentence: Codable, Equatable, Sendable {
        var parts: [Part]
        /// What happened to the last edit of this sentence: the reason it was refused, or what it changed.
        var note: String = ""
        var act: ActionLink?
    }

    enum Part: Equatable, Sendable {
        case words(String)
        /// A value the person edits: `chip` names it, `text` is how it reads now.
        case chip(String, text: String, entry: Entry, choices: [String] = [])
    }

    enum Entry: String, Codable, Sendable { case number, time, choice }
}

extension SettingsRendering.Part: Codable {
    private enum Key: String, CodingKey { case words, chip, text, entry, choices }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: Key.self)
        if let words = try values.decodeIfPresent(String.self, forKey: .words) {
            self = .words(words)
        } else {
            self = .chip(
                try values.decode(String.self, forKey: .chip), text: try values.decode(String.self, forKey: .text),
                entry: try values.decode(SettingsRendering.Entry.self, forKey: .entry),
                choices: try values.decode([String].self, forKey: .choices))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: Key.self)
        switch self {
        case .words(let words): try values.encode(words, forKey: .words)
        case .chip(let chip, let text, let entry, let choices):
            try values.encode(chip, forKey: .chip)
            try values.encode(text, forKey: .text)
            try values.encode(entry, forKey: .entry)
            try values.encode(choices, forKey: .choices)
        }
    }
}

struct LineRendering: Codable, Equatable, Sendable {
    var text: String
    var act: ActionLink?
}

extension MachineView: Codable {
    private enum Key: String, CodingKey {
        case kind, text, cites
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: Key.self)
        switch try values.decode(String.self, forKey: .kind) {
        case "heading": self = .heading(text: try values.decode(String.self, forKey: .text))
        case "text":
            self = .text(
                text: try values.decode(String.self, forKey: .text),
                cites: try values.decode([CiteChip].self, forKey: .cites))
        case "facts": self = .facts(try FactsRendering(from: decoder))
        case "grid": self = .grid(try GridRendering(from: decoder))
        case "picker": self = .picker(try PickerRendering(from: decoder))
        case "status": self = .status(try StatusRendering(from: decoder))
        case "line": self = .line(try LineRendering(from: decoder))
        case "settings": self = .settings(try SettingsRendering(from: decoder))
        case "erased": self = .erased(note: try Erased(from: decoder).note)
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "unknown kind"))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: Key.self)
        switch self {
        case .heading(let text):
            try values.encode("heading", forKey: .kind)
            try values.encode(text, forKey: .text)
        case .text(let text, let cites):
            try values.encode("text", forKey: .kind)
            try values.encode(text, forKey: .text)
            try values.encode(cites, forKey: .cites)
        case .facts(let facts):
            try values.encode("facts", forKey: .kind)
            try facts.encode(to: encoder)
        case .grid(let grid):
            try values.encode("grid", forKey: .kind)
            try grid.encode(to: encoder)
        case .picker(let picker):
            try values.encode("picker", forKey: .kind)
            try picker.encode(to: encoder)
        case .status(let status):
            try values.encode("status", forKey: .kind)
            try status.encode(to: encoder)
        case .settings(let settings):
            try values.encode("settings", forKey: .kind)
            try settings.encode(to: encoder)
        case .line(let line):
            try values.encode("line", forKey: .kind)
            try line.encode(to: encoder)
        case .erased(let note):
            try values.encode("erased", forKey: .kind)
            try Erased(note: note).encode(to: encoder)
        }
    }

    private struct Erased: Codable {
        var note: String
    }
}
