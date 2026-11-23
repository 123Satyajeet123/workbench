import Foundation

/// The stored lines a page's words rest on: the line each fact quotes, and the current line of each paragraph of the
/// person. A cite of a fact or of a paragraph is a cite of one of these lines.
public struct PageGrounds: Sendable, Equatable {
    /// The line of each fact's quote, by the fact's id. A fact whose quote is not from a stored line has none.
    public var facts: [Int64: Data]
    public var notes: [BlockID: Data]

    public init(facts: [Int64: Data] = [:], notes: [BlockID: Data] = [:]) {
        self.facts = facts
        self.notes = notes
    }

    /// The lines a model read when it was shown `page` and `items`: the page's paragraphs in page order, then the
    /// quote lines of the facts in their order, numbered from 1 in that order.
    func window(of page: MachinePage, items: [Item]) -> [WindowLine] {
        let paragraphs = page.order.compactMap { block -> Data? in
            if case .note(let id) = block { notes[id] } else { nil }
        }
        let quotes = items.compactMap { $0.id.flatMap { facts[$0] } }
        return (paragraphs + quotes).enumerated().map { WindowLine(number: Int64($0.offset + 1), lineID: $0.element) }
    }
}
