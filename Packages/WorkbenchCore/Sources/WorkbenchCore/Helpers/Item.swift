import Foundation
import Kernel

/// One thing a helper proposed: its fields, the evidence it cites, the words it relied on, and the founder's mark.
public struct Item: Sendable, Equatable, Identifiable {
    public var id: Int64?
    public var task: String
    public var day: WorkDay
    /// The chat for a chat helper; empty otherwise.
    public var scope: String
    public var source: SourceKind
    public var citeFirst: Int64
    public var citeLast: Int64
    public var start: Date
    public var end: Date
    public var fields: [String: String]
    /// Empty when `isSourceDeleted`.
    public var quote: String
    /// The message this item came from was deleted: its words are gone, and the item stays with its marks.
    public var isSourceDeleted = false
    public var state: Mark
    /// The model run that read it; nil for a fact the person typed.
    public var run: RunID?
    /// The chance the app picked this item to ask about; nil when it did not pick it. A mark on a picked item is an
    /// audit mark: valid evidence of the helper's error rate, because the founder did not choose it.
    public var askedWith: Double?
    /// How it ended: a close, a replacement by another fact, or a withdrawal; nil while it is open or for an item that
    /// never opens.
    public var closed: Closed?
    /// A model read that a line closes it, and nobody has acted on it since. A person confirms or ignores it.
    public var proposedClose: Closed?
    /// The due time the latest `due_changed` event gave it; nil when no line changed it.
    public var dueChanged: Due?
    /// Set when the founder hid the item or snoozed it; nil otherwise. See `isHidden(at:)`.
    public var hiding: Hiding?
    /// Where the quote is in the line it came from. Nil for an item whose quote is not from a line: a fact the person
    /// typed, or a finding that quotes the words of a fact it cites.
    public var quoteSpan: QuoteSpan?
    /// Who may read it: the join of the labels of what it cites and of every line of its window. Nil when that is not known, which no reader satisfies.
    public var label: Label?
    /// How far it may be trusted: no more than the least trusted line it rests on.
    public var authority: Authority

    /// The quote as a card shows it: in quotation marks, or why there is none.
    public var quotedWords: String { isSourceDeleted ? "The message this came from was deleted" : "“\(quote)”" }

    public enum Hiding: Sendable, Equatable {
        case hidden
        case snoozed(until: Date)
    }

    public struct Closed: Sendable, Equatable {
        public var outcome: String
        /// The closing words; nil when the founder closed it by hand.
        public var quote: String?
        public var at: Date
    }

    public init(
        id: Int64? = nil, task: String, day: WorkDay, scope: String, source: SourceKind, citeFirst: Int64,
        citeLast: Int64, start: Date, end: Date, fields: [String: String], quote: String, state: Mark = .proposed,
        run: RunID?, askedWith: Double? = nil, quoteSpan: QuoteSpan? = nil, label: Label? = nil,
        authority: Authority = .unknown, due: Due? = nil
    ) {
        self.id = id
        self.task = task
        self.day = day
        self.scope = scope
        self.source = source
        self.citeFirst = citeFirst
        self.citeLast = citeLast
        self.start = start
        self.end = end
        var fields = fields
        if let due, let json = try? Coding.json(due) { fields[Self.dueField] = json }
        self.fields = fields
        self.quote = quote
        self.state = state
        self.run = run
        self.askedWith = askedWith
        self.quoteSpan = quoteSpan
        self.label = label
        self.authority = authority
    }

    /// Whether the founder's hide or snooze keeps the item off the Today, People and Projects lists at `now`: a
    /// snooze ends at its date.
    public func isHidden(at now: Date) -> Bool {
        switch hiding {
        case nil: false
        case .hidden: true
        case .snoozed(let until): now < until
        }
    }

    /// The field that holds the store ids of the facts a finding cites, as a comma-separated list.
    static let factsField = "facts"

    /// The field that holds the due time a fact was opened with, as JSON of a `Due`. Code writes it: the verifier
    /// from a time record, or the store from a day a person typed. It holds none of a message's words.
    static let dueField = "due"

    public subscript(field: String) -> String { fields[field] ?? "" }
}
