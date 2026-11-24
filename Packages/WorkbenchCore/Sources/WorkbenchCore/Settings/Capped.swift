import Foundation

/// The first items a cap let through, and how many it left out. A cap that drops items must say how many.
public struct Capped<Element: Sendable>: Sendable, RandomAccessCollection, ExpressibleByArrayLiteral {
    public var items: [Element]
    public var leftOut: Int

    public init(arrayLiteral elements: Element...) {
        self.init(elements)
    }

    public init(_ items: [Element], leftOut: Int = 0) {
        self.items = items
        self.leftOut = leftOut
    }

    public var startIndex: Int { items.startIndex }
    public var endIndex: Int { items.endIndex }
    public subscript(position: Int) -> Element { items[position] }
}

/// A count of what a reading did not show the model, because a cap in `RunSettings` cut it. The reading's run keeps
/// one row for each part it cut, in the rows of refused proposals (`drop_reason`), under the rule `left_out`.
public struct LeftOut: Sendable, Equatable {
    public enum Part: String, Sendable, CaseIterable {
        case openFacts = "open_facts"
        case objects
        case pageCharacters = "page_characters"
        case memoryEntries = "memory_entries"
    }

    public var part: Part
    public var count: Int

    public init(_ part: Part, count: Int) {
        self.part = part
        self.count = count
    }

    private struct Proposal: Codable { var count: Int }

    var drop: Drop? {
        guard count > 0, let proposal = try? Coding.json(Proposal(count: count)) else { return nil }
        return Drop(part: part.rawValue, ordinal: 0, rule: .leftOut, proposal: proposal)
    }

    init?(_ drop: Drop) {
        guard drop.rule == .leftOut, let part = Part(rawValue: drop.part),
            let proposal = try? Coding.value(Proposal.self, from: drop.proposal)
        else { return nil }
        self.init(part, count: proposal.count)
    }
}

extension Queries {
    /// What the reading that made `run` did not show the model, because a cap cut it. Empty when nothing was cut.
    public func leftOut(of run: RunID) throws -> [LeftOut] {
        try dropReasons(of: run).compactMap(LeftOut.init)
    }
}

extension RecordedModel {
    /// Keeps the counts a cap cut from what the run's model was shown. A count of zero keeps nothing.
    func record(_ leftOut: [LeftOut], of run: RunID) throws {
        try record(leftOut.compactMap(\.drop), of: run)
    }
}
