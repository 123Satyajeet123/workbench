import Foundation

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
    public var quote: String
    public var state: Mark
    /// The model run that read it; nil for a fact the person typed.
    public var run: RunID?
    /// The chance the app picked this item to ask about; nil when it did not pick it. A mark on a picked item is an
    /// audit mark: valid evidence of the helper's error rate, because the founder did not choose it.
    public var askedWith: Double?
    /// How a later line, or the founder, closed it; nil while it is open or for an item that never opens.
    public var closed: Closed?
    /// Set when the founder hid the item or snoozed it; nil otherwise. See `isHidden(at:)`.
    public var hiding: Hiding?

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
        run: RunID?, askedWith: Double? = nil
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
        self.fields = fields
        self.quote = quote
        self.state = state
        self.run = run
        self.askedWith = askedWith
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

    public subscript(field: String) -> String { fields[field] ?? "" }

    /// Whether a new reading's item says what a marked one already says, so the mark stands for it. A finding of facts
    /// repeats one that cites the same facts and has the same value in each of the spec's `choices` fields.
    func repeats(_ marked: Item, citation: HelperSpec.Citation, choices: [String] = []) -> Bool {
        switch citation {
        case .range: start < marked.end && marked.start < end
        case .one: citeFirst == marked.citeFirst && fields == marked.fields && quote == marked.quote
        case .facts:
            self[Self.factsField] == marked[Self.factsField] && choices.allSatisfy { self[$0] == marked[$0] }
        }
    }
}
