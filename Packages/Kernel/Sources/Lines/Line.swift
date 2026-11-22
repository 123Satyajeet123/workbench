// Source: built (research 56 §1, research 45 §4 evidence line; ADR-014). The occurrence rule replaces screenpipe's
// screen-position ordinal (research E-R1 §4.2 defect 2, §4.3).

import Foundation

/// One line of evidence as a reader gives it: what it is about, its text, and the reader that read it. Two lines are
/// equal when their ids are equal.
public struct Line: Hashable, Sendable {
    public let entity: EntityKey
    /// The text as read, in NFC, with its line breaks and spacing. Empty for a tombstone.
    public let text: String
    public let readerVersion: String
    public let content: ContentHash

    public init(entity: EntityKey, text: String, readerVersion: String) {
        self.init(entity: entity, text: text, readerVersion: readerVersion, content: ContentHash(text: text))
    }

    private init(entity: EntityKey, text: String, readerVersion: String, content: ContentHash) {
        self.entity = entity
        self.text = text.precomposedStringWithCanonicalMapping
        self.readerVersion = readerVersion
        self.content = content
    }

    /// The line that stands for a message deleted at its source: no text, and an id that no text can have.
    public static func tombstone(entity: EntityKey, readerVersion: String) -> Line {
        Line(entity: entity, text: "", readerVersion: readerVersion, content: .tombstone)
    }

    public var id: LineID { LineID(entity: entity, content: content) }
    public var isTombstone: Bool { content == .tombstone }

    public static func == (lhs: Line, rhs: Line) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// The lines of one read of a screen container, in reading order, one per text whose identity text is not
    /// empty. Equal texts in one container are a multiset: the k-th copy in reading order has ordinal k. A read that
    /// shows one copy maps onto ordinal 0.
    public static func screen(container: String, texts: [String], readerVersion: String) throws(EntityKeyError)
        -> [Line]
    {
        var copies: [ContentHash: UInt32] = [:]
        var lines: [Line] = []
        for text in texts {
            let identityText = IdentityText.normalize(text)
            guard !identityText.isEmpty else { continue }
            let content = ContentHash(identityText: identityText)
            let ordinal = copies[content, default: 0]
            copies[content] = ordinal + 1
            let entity = try EntityKey.screen(container: container, content: content, ordinal: ordinal)
            lines.append(Line(entity: entity, text: text, readerVersion: readerVersion, content: content))
        }
        return lines
    }
}
