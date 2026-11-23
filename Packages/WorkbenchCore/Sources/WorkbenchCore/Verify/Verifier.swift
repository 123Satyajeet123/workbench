import Foundation

/// Where a quote is in the line it came from: the number of the line, which of its quotable texts, and the offsets of
/// the quote in that text, counted in Unicode scalars of its normal form C. The end is past the last character.
public struct QuoteSpan: Sendable, Equatable {
    public var line: Int64
    public var part: Int
    public var start: Int
    public var end: Int

    public init(line: Int64, part: Int, start: Int, end: Int) {
        self.line = line
        self.part = part
        self.start = start
        self.end = end
    }
}

/// The one check that every machine's reading passes before anything is kept: a function of a proposal and the window
/// the model was shown, that keeps the proposal or drops it with the rule it broke. A rule reads where a proposal
/// points and what it quotes, never what it means. A check that fails with an error drops the proposal.
public struct Verifier: Sendable {
    public struct Settings: Codable, Sendable, Equatable {
        /// The fewest words a quote may have, unless it is a whole line. Nil: the rule is off.
        public var minimumQuoteWords: Int?
        /// The hours that parts of the day stand for when a time is resolved. Nil: the defaults of `DayHours`.
        public var dayHours: DayHours?

        public init(minimumQuoteWords: Int? = nil, dayHours: DayHours? = nil) {
            self.minimumQuoteWords = minimumQuoteWords
            self.dayHours = dayHours
        }
    }

    public let window: EvidenceSet
    public let settings: Settings
    /// The owner's time zone: the zone a time in a line is resolved in.
    public let zone: TimeZone

    public init(window: EvidenceSet, settings: Settings = Settings(), zone: TimeZone = .current) {
        self.window = window
        self.settings = settings
        self.zone = zone
    }

    /// The verdict of one proposal's checks. A check refuses with its rule, or fails with another error, and then the
    /// proposal is dropped as `verifierError`: it was not fully checked, so it is not kept.
    public func verdict<Value: Sendable>(_ checks: () throws -> Value) -> Judgment<Value> {
        do {
            return .accepted(try checks())
        } catch let refusal as Refusal {
            return .dropped(refusal.rule)
        } catch {
            return .dropped(.verifierError)
        }
    }

    /// The verdicts of one list of a reply, in order: the values kept, and a drop for each proposal refused and for
    /// each value that `isRepeat` finds among the values kept before it.
    public func settle<Proposal: Encodable & Sendable, Value: Sendable>(
        _ proposals: [Proposal], part: String, check: (Proposal) throws -> Value,
        isRepeat: (Value, [Value]) -> Bool
    ) throws -> (kept: [Value], drops: [Drop]) {
        var kept: [Value] = []
        var drops: [Drop] = []
        for (ordinal, proposal) in proposals.enumerated() {
            let drop = { (rule: DropRule) in
                Drop(part: part, ordinal: ordinal, rule: rule, proposal: try Coding.json(proposal))
            }
            switch verdict({ try check(proposal) }) {
            case .accepted(let value) where !isRepeat(value, kept): kept.append(value)
            case .accepted: drops.append(try drop(.repeatInReading))
            case .dropped(let rule): drops.append(try drop(rule))
            }
        }
        return (kept, drops)
    }

    /// The line a proposal cites: it is in the window, and no earlier reading saw it.
    func newLine(_ number: Int64) throws -> Evidence {
        guard !window.isRead(number), let line = window.lines.first(where: { $0.id == number }) else {
            throw Refusal(.outsideWindow)
        }
        return line
    }

    /// Where `words` is in one of `lines`, found exactly after the fold of `FoldedText`. No near match counts.
    func quote(_ words: String, in lines: [Evidence]) throws -> QuoteSpan {
        let quote = FoldedText(words)
        for line in lines {
            for (part, text) in line.quotable.enumerated() {
                let source = FoldedText(text)
                guard let range = source.range(of: quote) else { continue }
                try requireStrength(of: quote, isWhole: range.count == source.scalars.count)
                let span = source.source(of: range)
                return QuoteSpan(line: line.id, part: part, start: span.lowerBound, end: span.upperBound)
            }
        }
        throw Refusal(.quoteNotInLines)
    }

    /// The line of `lines` that holds `words`, found as a quote is and with no minimum length: a time is often one
    /// word. Nil for no words.
    func lineHolding(_ words: String, in lines: [Evidence]) throws -> Evidence? {
        let words = FoldedText(words)
        guard !words.scalars.isEmpty else { return nil }
        guard let line = lines.first(where: { $0.quotable.contains { FoldedText($0).range(of: words) != nil } }) else {
            throw Refusal(.quoteNotInLines)
        }
        return line
    }

    /// Like `quote(_:in:)`, and when no line holds the words, the quote of a fact the proposal cites may. That gives no
    /// span, because the words are not in a line.
    func quote(_ words: String, in lines: [Evidence], orIn facts: [Item]) throws -> QuoteSpan? {
        do {
            return try quote(words, in: lines)
        } catch let refusal as Refusal where refusal.rule == .quoteNotInLines {
            let quote = FoldedText(words)
            guard let held = facts.map({ FoldedText($0.quote) }).first(where: { $0.range(of: quote) != nil }) else {
                throw refusal
            }
            try requireStrength(of: quote, isWhole: held.scalars == quote.scalars)
            return nil
        }
    }

    private func requireStrength(of quote: FoldedText, isWhole: Bool) throws {
        guard let minimum = settings.minimumQuoteWords, !isWhole else { return }
        let words = quote.text.split { !$0.isLetter && !$0.isNumber }
        guard words.count >= minimum else { throw Refusal(.quoteTooShort) }
    }
}
