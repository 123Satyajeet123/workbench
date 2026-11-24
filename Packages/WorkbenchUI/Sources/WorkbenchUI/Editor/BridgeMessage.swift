import Foundation

/// The bridge between the editor in the web view and Swift. The contract is `Editor/contract/bridge.schema.json`; each
/// type here is one definition of it, and `BridgeContract` keeps the two in step.

/// What the editor sends to Swift.
enum EditorMessage: Equatable, Sendable {
    case ready(contract: Int)
    case ops(seq: Int, ops: [EditorOp])
    case open(OpenTarget)
    case blocked(directive: String, uri: String)
    case idle
    case layout(height: Int, caret: CaretBox?)
}

/// Where the caret is in the page, in points from its top.
struct CaretBox: Codable, Equatable, Sendable {
    var top: Int
    var bottom: Int
}

/// One thing the person did on the page.
enum EditorOp: Equatable, Sendable {
    case insert(id: String, after: String?, text: String)
    case update(id: String, text: String)
    case move(id: String, after: String?)
    case delete(id: String)
    case merge(id: String, into: String)
    case mark(fact: Int64, FactMark)
    /// The person chose another form or group field for a facts view. Swift asks the gate and stores the change.
    case view(block: String, form: String, groupBy: String)
    /// The person changed the words of a field of the document. Swift decides what they mean.
    case field(id: String, text: String)
    /// The person retyped the heading of a facts view.
    case heading(block: String, text: String)
    /// The person edited the value of one chip of a setting sentence.
    case setting(key: String, value: String)
    /// The person ended a line that starts with /ask.
    case ask(text: String)
}

enum FactMark: String, Codable, Equatable, Sendable {
    case right, wrong, done
}

enum OpenTarget: Equatable, Sendable {
    case cite(ref: String)
    case link(url: String)
    case picker(source: String)
    case action(Action)

    enum Action: String, Codable, Sendable { case read, more, choose, brief, criteria, accept, decline, undo }
}

/// What Swift sends to the editor.
enum HostMessage: Equatable, Sendable {
    case environment(EditorEnvironment)
    case load([PageBlockData])
    case apply([PageChange])
    case ack(seq: Int, renames: [BlockRename])
    case flush
}

struct EditorEnvironment: Codable, Equatable, Sendable {
    enum Appearance: String, Codable, Sendable { case light, dark }

    var appearance: Appearance
    var reduceMotion: Bool
    /// False when Swift cannot write the page: the person reads it and types nothing.
    var editable: Bool = true
    var tokens: [String: String]
}

struct BlockRename: Codable, Equatable, Sendable {
    var from: String
    var to: String
}

/// One block of the page as the editor shows it.
enum PageBlockData: Equatable, Sendable {
    case note(id: String, text: String)
    case machine(id: String, view: MachineView, standing: BlockStanding)
    /// Words of the document that the person edits where they stand, and Swift reads as a setting of the machine.
    case field(id: String, look: FieldLook, hint: String, text: String)

    var id: String {
        switch self {
        case .note(let id, _), .machine(let id, _, _), .field(let id, _, _, _): id
        }
    }
}

enum FieldLook: String, Codable, Sendable {
    case title, body
}

/// A change Swift committed, in the order it must be shown.
enum PageChange: Equatable, Sendable {
    case insert(after: String?, block: PageBlockData)
    case update(block: PageBlockData)
    case move(id: String, after: String?)
    case remove(id: String)
}

// MARK: - Coding

private struct Key: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(_ name: String) { stringValue = name }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

private func discriminator(_ decoder: any Decoder, _ name: String) throws -> (KeyedDecodingContainer<Key>, String) {
    let values = try decoder.container(keyedBy: Key.self)
    return (values, try values.decode(String.self, forKey: Key(name)))
}

private func unknown(_ kind: String, in values: KeyedDecodingContainer<Key>) -> DecodingError {
    DecodingError.dataCorrupted(.init(codingPath: values.codingPath, debugDescription: "unknown \(kind)"))
}

extension EditorMessage: Codable {
    init(from decoder: any Decoder) throws {
        let (values, type) = try discriminator(decoder, "type")
        switch type {
        case "ready": self = .ready(contract: try values.decode(Int.self, forKey: Key("contract")))
        case "ops":
            self = .ops(
                seq: try values.decode(Int.self, forKey: Key("seq")),
                ops: try values.decode([EditorOp].self, forKey: Key("ops")))
        case "open": self = .open(try values.decode(OpenTarget.self, forKey: Key("target")))
        case "blocked":
            self = .blocked(
                directive: try values.decode(String.self, forKey: Key("directive")),
                uri: try values.decode(String.self, forKey: Key("uri")))
        case "idle": self = .idle
        case "layout":
            self = .layout(
                height: try values.decode(Int.self, forKey: Key("height")),
                caret: try values.decode(CaretBox?.self, forKey: Key("caret")))
        default: throw unknown(type, in: values)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: Key.self)
        switch self {
        case .ready(let contract):
            try values.encode("ready", forKey: Key("type"))
            try values.encode(contract, forKey: Key("contract"))
        case .ops(let seq, let ops):
            try values.encode("ops", forKey: Key("type"))
            try values.encode(seq, forKey: Key("seq"))
            try values.encode(ops, forKey: Key("ops"))
        case .open(let target):
            try values.encode("open", forKey: Key("type"))
            try values.encode(target, forKey: Key("target"))
        case .blocked(let directive, let uri):
            try values.encode("blocked", forKey: Key("type"))
            try values.encode(directive, forKey: Key("directive"))
            try values.encode(uri, forKey: Key("uri"))
        case .idle: try values.encode("idle", forKey: Key("type"))
        case .layout(let height, let caret):
            try values.encode("layout", forKey: Key("type"))
            try values.encode(height, forKey: Key("height"))
            try values.encode(caret, forKey: Key("caret"))
        }
    }
}

extension EditorOp: Codable {
    init(from decoder: any Decoder) throws {
        let (values, op) = try discriminator(decoder, "op")
        func string(_ name: String) throws -> String { try values.decode(String.self, forKey: Key(name)) }
        func place() throws -> String? { try values.decode(String?.self, forKey: Key("after")) }
        switch op {
        case "insert": self = .insert(id: try string("id"), after: try place(), text: try string("text"))
        case "update": self = .update(id: try string("id"), text: try string("text"))
        case "move": self = .move(id: try string("id"), after: try place())
        case "delete": self = .delete(id: try string("id"))
        case "merge": self = .merge(id: try string("id"), into: try string("into"))
        case "mark":
            self = .mark(
                fact: try values.decode(Int64.self, forKey: Key("fact")),
                try values.decode(FactMark.self, forKey: Key("mark")))
        case "view": self = .view(block: try string("id"), form: try string("form"), groupBy: try string("groupBy"))
        case "field": self = .field(id: try string("id"), text: try string("text"))
        case "heading": self = .heading(block: try string("id"), text: try string("text"))
        case "setting": self = .setting(key: try string("key"), value: try string("value"))
        case "ask": self = .ask(text: try string("text"))
        default: throw unknown(op, in: values)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: Key.self)
        switch self {
        case .insert(let id, let after, let text):
            try values.encode("insert", forKey: Key("op"))
            try values.encode(id, forKey: Key("id"))
            try values.encode(after, forKey: Key("after"))
            try values.encode(text, forKey: Key("text"))
        case .update(let id, let text):
            try values.encode("update", forKey: Key("op"))
            try values.encode(id, forKey: Key("id"))
            try values.encode(text, forKey: Key("text"))
        case .move(let id, let after):
            try values.encode("move", forKey: Key("op"))
            try values.encode(id, forKey: Key("id"))
            try values.encode(after, forKey: Key("after"))
        case .delete(let id):
            try values.encode("delete", forKey: Key("op"))
            try values.encode(id, forKey: Key("id"))
        case .merge(let id, let into):
            try values.encode("merge", forKey: Key("op"))
            try values.encode(id, forKey: Key("id"))
            try values.encode(into, forKey: Key("into"))
        case .mark(let fact, let mark):
            try values.encode("mark", forKey: Key("op"))
            try values.encode(fact, forKey: Key("fact"))
            try values.encode(mark, forKey: Key("mark"))
        case .view(let block, let form, let groupBy):
            try values.encode("view", forKey: Key("op"))
            try values.encode(block, forKey: Key("id"))
            try values.encode(form, forKey: Key("form"))
            try values.encode(groupBy, forKey: Key("groupBy"))
        case .field(let id, let text):
            try values.encode("field", forKey: Key("op"))
            try values.encode(id, forKey: Key("id"))
            try values.encode(text, forKey: Key("text"))
        case .heading(let block, let text):
            try values.encode("heading", forKey: Key("op"))
            try values.encode(block, forKey: Key("id"))
            try values.encode(text, forKey: Key("text"))
        case .setting(let key, let value):
            try values.encode("setting", forKey: Key("op"))
            try values.encode(key, forKey: Key("key"))
            try values.encode(value, forKey: Key("value"))
        case .ask(let text):
            try values.encode("ask", forKey: Key("op"))
            try values.encode(text, forKey: Key("text"))
        }
    }
}

extension OpenTarget: Codable {
    init(from decoder: any Decoder) throws {
        let (values, kind) = try discriminator(decoder, "kind")
        switch kind {
        case "cite": self = .cite(ref: try values.decode(String.self, forKey: Key("ref")))
        case "link": self = .link(url: try values.decode(String.self, forKey: Key("url")))
        case "picker": self = .picker(source: try values.decode(String.self, forKey: Key("source")))
        case "action": self = .action(try values.decode(Action.self, forKey: Key("name")))
        default: throw unknown(kind, in: values)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: Key.self)
        switch self {
        case .cite(let ref):
            try values.encode("cite", forKey: Key("kind"))
            try values.encode(ref, forKey: Key("ref"))
        case .link(let url):
            try values.encode("link", forKey: Key("kind"))
            try values.encode(url, forKey: Key("url"))
        case .picker(let source):
            try values.encode("picker", forKey: Key("kind"))
            try values.encode(source, forKey: Key("source"))
        case .action(let action):
            try values.encode("action", forKey: Key("kind"))
            try values.encode(action, forKey: Key("name"))
        }
    }
}

extension HostMessage: Codable {
    init(from decoder: any Decoder) throws {
        let (values, type) = try discriminator(decoder, "type")
        switch type {
        case "environment": self = .environment(try EditorEnvironment(from: decoder))
        case "load": self = .load(try values.decode([PageBlockData].self, forKey: Key("blocks")))
        case "apply": self = .apply(try values.decode([PageChange].self, forKey: Key("changes")))
        case "ack":
            self = .ack(
                seq: try values.decode(Int.self, forKey: Key("seq")),
                renames: try values.decode([BlockRename].self, forKey: Key("renames")))
        case "flush": self = .flush
        default: throw unknown(type, in: values)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: Key.self)
        switch self {
        case .environment(let environment):
            try values.encode("environment", forKey: Key("type"))
            try values.encode(environment.appearance, forKey: Key("appearance"))
            try values.encode(environment.reduceMotion, forKey: Key("reduceMotion"))
            try values.encode(environment.editable, forKey: Key("editable"))
            try values.encode(environment.tokens, forKey: Key("tokens"))
        case .load(let blocks):
            try values.encode("load", forKey: Key("type"))
            try values.encode(blocks, forKey: Key("blocks"))
        case .apply(let changes):
            try values.encode("apply", forKey: Key("type"))
            try values.encode(changes, forKey: Key("changes"))
        case .ack(let seq, let renames):
            try values.encode("ack", forKey: Key("type"))
            try values.encode(seq, forKey: Key("seq"))
            try values.encode(renames, forKey: Key("renames"))
        case .flush: try values.encode("flush", forKey: Key("type"))
        }
    }
}

extension PageBlockData: Codable {
    init(from decoder: any Decoder) throws {
        let (values, kind) = try discriminator(decoder, "kind")
        let id = try values.decode(String.self, forKey: Key("id"))
        switch kind {
        case "note": self = .note(id: id, text: try values.decode(String.self, forKey: Key("text")))
        case "machine":
            self = .machine(
                id: id, view: try values.decode(MachineView.self, forKey: Key("view")),
                standing: try values.decode(BlockStanding.self, forKey: Key("standing")))
        case "field":
            self = .field(
                id: id, look: try values.decode(FieldLook.self, forKey: Key("look")),
                hint: try values.decode(String.self, forKey: Key("hint")),
                text: try values.decode(String.self, forKey: Key("text")))
        default: throw unknown(kind, in: values)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: Key.self)
        switch self {
        case .note(let id, let text):
            try values.encode("note", forKey: Key("kind"))
            try values.encode(id, forKey: Key("id"))
            try values.encode(text, forKey: Key("text"))
        case .machine(let id, let view, let standing):
            try values.encode("machine", forKey: Key("kind"))
            try values.encode(id, forKey: Key("id"))
            try values.encode(view, forKey: Key("view"))
            try values.encode(standing, forKey: Key("standing"))
        case .field(let id, let look, let hint, let text):
            try values.encode("field", forKey: Key("kind"))
            try values.encode(id, forKey: Key("id"))
            try values.encode(look, forKey: Key("look"))
            try values.encode(hint, forKey: Key("hint"))
            try values.encode(text, forKey: Key("text"))
        }
    }
}

extension PageChange: Codable {
    init(from decoder: any Decoder) throws {
        let (values, change) = try discriminator(decoder, "change")
        func place() throws -> String? { try values.decode(String?.self, forKey: Key("after")) }
        switch change {
        case "insert":
            self = .insert(after: try place(), block: try values.decode(PageBlockData.self, forKey: Key("block")))
        case "update": self = .update(block: try values.decode(PageBlockData.self, forKey: Key("block")))
        case "move": self = .move(id: try values.decode(String.self, forKey: Key("id")), after: try place())
        case "remove": self = .remove(id: try values.decode(String.self, forKey: Key("id")))
        default: throw unknown(change, in: values)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: Key.self)
        switch self {
        case .insert(let after, let block):
            try values.encode("insert", forKey: Key("change"))
            try values.encode(after, forKey: Key("after"))
            try values.encode(block, forKey: Key("block"))
        case .update(let block):
            try values.encode("update", forKey: Key("change"))
            try values.encode(block, forKey: Key("block"))
        case .move(let id, let after):
            try values.encode("move", forKey: Key("change"))
            try values.encode(id, forKey: Key("id"))
            try values.encode(after, forKey: Key("after"))
        case .remove(let id):
            try values.encode("remove", forKey: Key("change"))
            try values.encode(id, forKey: Key("id"))
        }
    }
}
