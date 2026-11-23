import Foundation

/// The kinds of event in the life of a fact. The raw value is what the store keeps (research 59 §1 Lifecycle row).
public enum EventKind: String, CaseIterable, Sendable {
    /// The fact exists. Code writes it when the item is stored.
    case open
    /// Another line says the same again.
    case restate
    /// Another line gives a new date for the same fact.
    case dueChanged = "due_changed"
    /// Another fact replaces it.
    case supersede
    /// A model read that a line closes it. A person confirms or ignores that.
    case closeProposed = "close_proposed"
    case close
    case reopen
    /// The person says it was never a fact.
    case withdraw
    /// A model could not tell if it is the same as an open fact.
    case flag
    case hide
    case snooze
    case unhide

    /// The kinds that end a fact or bring it back. The latest of them, by valid time, is the fact's status.
    public static let statusKinds: [EventKind] = [.supersede, .close, .reopen, .withdraw]

    /// The kinds a model may write. Each carries the line and the quote that show it.
    public static let modelKinds: [EventKind] = [.open, .restate, .dueChanged, .supersede, .closeProposed, .flag]
}

/// How a proposed item relates to the open facts the model was shown, as the model said it and code checked it. A
/// target is the store id of an open fact, found from its handle.
public enum Relation: Sendable, Equatable {
    case new
    /// The same fact again: another citation, and maybe another date.
    case sameAs(Int64)
    case supersedes(Int64)
    case closes(Int64, outcome: String)
    case unsure

    /// The open fact it points at; nil for a relation that points at none.
    public var target: Int64? {
        switch self {
        case .new, .unsure: nil
        case .sameAs(let id), .supersedes(let id), .closes(let id, _): id
        }
    }

    /// The raw names of the relations the model may name, as the schema lists them.
    public static let names = ["new", "same_as", "supersedes", "closes", "unsure"]
}

/// What a reading says about a fact: an event to write on it, with the line and the words that show it.
public struct Link: Sendable, Equatable {
    /// The fact the event is on: one already stored, or one this reading opens, by its place in `Result.items`.
    public enum Subject: Sendable, Equatable {
        case stored(Int64)
        case opened(Int)
    }

    public enum Effect: Sendable, Equatable {
        case restate
        case dueChanged(String)
        /// The fact is replaced by the one opened at this place in `Result.items`.
        case supersede(by: Int)
        case closeProposed(outcome: String)
        case flag
    }

    public var subject: Subject
    public var effect: Effect
    public var line: Int64
    public var quote: String
    /// When the line was said: the valid time of the event.
    public var at: Date

    public var kind: EventKind {
        switch effect {
        case .restate: .restate
        case .dueChanged: .dueChanged
        case .supersede: .supersede
        case .closeProposed: .closeProposed
        case .flag: .flag
        }
    }
}
