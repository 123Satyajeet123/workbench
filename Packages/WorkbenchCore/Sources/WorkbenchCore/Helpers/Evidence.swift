import Foundation

/// One numbered line a helper's model reads: a message, a screen session. A quote must come from `quotable`.
public struct Evidence: Sendable, Equatable {
    public var id: Int64
    public var start: Date
    /// Nil for a moment, such as a message.
    public var end: Date?
    /// What follows the time on the line.
    public var line: String
    /// The texts a quote may be taken from.
    public var quotable: [String]

    public init(id: Int64, start: Date, end: Date? = nil, line: String, quotable: [String]) {
        self.id = id
        self.start = start
        self.end = end
        self.line = line
        self.quotable = quotable
    }

    func contains(quote: String) -> Bool { quotable.contains { $0.contains(quote: quote) } }
}

/// What a source gives a helper for one day: the lines, and named sets such as the group's members.
public struct EvidenceSet: Sendable, Equatable {
    public var lines: [Evidence]
    public var context: [String: [String]]

    public init(lines: [Evidence], context: [String: [String]] = [:]) {
        self.lines = lines
        self.context = context
    }
}

extension ScreenSession {
    public var evidence: Evidence {
        Evidence(
            id: Int64(number), start: start, end: end,
            line: [app, title, document ?? ""].filter { !$0.isEmpty }.joined(separator: " — "),
            quotable: [title, document ?? ""])
    }
}

extension Activity {
    /// A page's text as one evidence line: its site, title and the text on screen. Nil for an activity with no text.
    public var pageEvidence: Evidence? {
        guard let id, let text, !text.isEmpty else { return nil }
        let site = document.flatMap { URL(string: $0)?.host() } ?? app
        return Evidence(id: id, start: at, line: "\(site) — \(title): \(text)", quotable: [text])
    }
}
