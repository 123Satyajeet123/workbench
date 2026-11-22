import Foundation

public struct Item: Sendable, Equatable, Identifiable {
    public var id: Int64?
    public var task: String
    public var day: WorkDay
    public var scope: String
    public var source: SourceKind
    public var citeFirst: Int64
    public var citeLast: Int64
    public var start: Date
    public var end: Date
    public var fields: [String: String]
    public var quote: String
    public var state: Mark
    public var run: RunID?
    public var askedWith: Double?
    public var closed: Closed?
    public var hiding: Hiding?

    public enum Hiding: Sendable, Equatable {
        case hidden
        case snoozed(until: Date)
    }

    public struct Closed: Sendable, Equatable {
        public var outcome: String
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

    public func isHidden(at now: Date) -> Bool {
        switch hiding {
        case nil: false
        case .hidden: true
        case .snoozed(let until): now < until
        }
    }

    static let factsField = "facts"

    public subscript(field: String) -> String { fields[field] ?? "" }

    func repeats(_ marked: Item, citation: HelperSpec.Citation, choices: [String] = []) -> Bool {
        switch citation {
        case .range: start < marked.end && marked.start < end
        case .one: citeFirst == marked.citeFirst && fields == marked.fields && quote == marked.quote
        case .facts:
            self[Self.factsField] == marked[Self.factsField] && choices.allSatisfy { self[$0] == marked[$0] }
        }
    }
}
