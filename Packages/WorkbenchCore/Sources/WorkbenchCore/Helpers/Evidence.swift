import Foundation

public struct Evidence: Sendable, Equatable {
    public var id: Int64
    public var start: Date
    public var end: Date?
    public var line: String
    public var quotable: [String]

    public init(id: Int64, start: Date, end: Date? = nil, line: String, quotable: [String]) {
        self.id = id
        self.start = start
        self.end = end
        self.line = line.split(whereSeparator: \.isNewline).joined(separator: " ")
        self.quotable = quotable
    }

    func contains(quote: String) -> Bool { quotable.contains { $0.contains(quote: quote) } }
}

public struct EvidenceSet: Sendable, Equatable {
    public var lines: [Evidence]
    public var context: [String: [String]]
    public var readUpTo: Int64?

    public init(lines: [Evidence], context: [String: [String]] = [:], readUpTo: Int64? = nil) {
        self.lines = lines
        self.context = context
        self.readUpTo = readUpTo
    }

    public var newLines: [Evidence] { lines.filter { $0.id > (readUpTo ?? .min) } }

    public func after(_ last: Int64?, context: Int = 20) -> EvidenceSet {
        guard let last else { return self }
        let seen = lines.filter { $0.id <= last }.suffix(context)
        return EvidenceSet(lines: seen + lines.filter { $0.id > last }, context: self.context, readUpTo: last)
    }
}

extension ScreenSession {
    public var evidence: Evidence {
        Evidence(
            id: id, start: start, end: end,
            line: [app, title, document ?? ""].filter { !$0.isEmpty }.joined(separator: " — "),
            quotable: [title, document ?? ""])
    }
}

extension Activity {
    public var pageEvidence: Evidence? {
        guard let id, let text, !text.isEmpty else { return nil }
        let site = document.flatMap { URL(string: $0)?.host() } ?? app
        return Evidence(id: id, start: at, line: "\(site) — \(title): \(text)", quotable: [text])
    }
}
