import Foundation

/// What the person agreed to for a line: the kind of source and its label, as the evidence store names them.
public struct Consent: Sendable, Equatable, Hashable {
    public var kind: SourceKind
    public var label: String

    public init(kind: SourceKind, label: String) {
        self.kind = kind
        self.label = label
    }
}

/// One numbered line a helper's model reads: a message, a screen session. A quote must come from `quotable`.
public struct Evidence: Sendable, Equatable {
    public var id: Int64
    public var start: Date
    /// Nil for a moment, such as a message.
    public var end: Date?
    /// What follows the time on the line, kept on one line: a newline in a message cannot start a line of its own.
    public var line: String
    /// The texts a quote may be taken from.
    public var quotable: [String]
    /// The stored line behind this one, when its source keeps lines in the evidence store: a run records it, so the
    /// number a model cites resolves to this line later.
    public var lineID: Data?
    /// Who may read the line and how far it is trusted, as the store recorded them. Nil when the source keeps no
    /// stored line: the line then has no known label and its authority is unknown.
    public var provenance: Provenance?
    /// The consent that let the line in. Nil when the source keeps no stored line.
    public var consent: Consent?

    public init(
        id: Int64, start: Date, end: Date? = nil, line: String, quotable: [String], lineID: Data? = nil,
        provenance: Provenance? = nil, consent: Consent? = nil
    ) {
        self.id = id
        self.lineID = lineID
        self.provenance = provenance
        self.consent = consent
        self.start = start
        self.end = end
        self.line = line.split(whereSeparator: \.isNewline).joined(separator: " ")
        self.quotable = quotable
    }

    func contains(quote: String) -> Bool { quotable.contains { $0.contains(quote: quote) } }
}

/// What a source gives a helper for one day: the lines, and named sets such as the group's members.
public struct EvidenceSet: Sendable, Equatable {
    public var lines: [Evidence]
    public var context: [String: [String]]
    /// The numbers of lines an earlier reading saw: they are shown for context, and no item may cite them.
    public var read: Set<Int64>

    public init(lines: [Evidence], context: [String: [String]] = [:], read: Set<Int64> = []) {
        self.lines = lines
        self.context = context
        self.read = read
    }

    /// A source whose line numbers only grow: every line numbered up to `readUpTo` was read.
    public init(lines: [Evidence], context: [String: [String]] = [:], readUpTo: Int64) {
        self.init(lines: lines, context: context, read: Set(lines.map(\.id).filter { $0 <= readUpTo }))
    }

    /// Whether an earlier reading saw anything of this day.
    public var hasBeenRead: Bool { !read.isEmpty }

    public func isRead(_ number: Int64) -> Bool { read.contains(number) }

    /// Lines no earlier reading saw.
    public var newLines: [Evidence] { lines.filter { !isRead($0.id) } }

    /// The new lines, with up to `context` earlier lines before them so a reply such as "done" keeps its question.
    public func marking(read: Set<Int64>, context: Int = 20) -> EvidenceSet {
        guard !read.isEmpty else { return self }
        let marked = EvidenceSet(lines: lines, context: self.context, read: read)
        let seen = lines.filter { marked.isRead($0.id) }.suffix(context)
        return EvidenceSet(lines: seen + marked.newLines, context: self.context, read: read)
    }
}
