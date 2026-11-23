import Foundation

/// The name of a project note. A project has one note, so its id is the project's id: it is also the container of the
/// note's lines.
public struct NoteID: Hashable, Sendable {
    public let rawValue: String

    public init?(project: String) {
        let text = project.precomposedStringWithCanonicalMapping
        guard !text.isEmpty else { return nil }
        rawValue = text
    }
}

/// The name of one paragraph of a note. The editor makes it when the paragraph is made and keeps it while the
/// paragraph lives. A name is never used again after its block ended.
public struct BlockID: Hashable, Sendable {
    public let rawValue: String

    public init() { rawValue = UUID().uuidString }

    public init?(_ rawValue: String) {
        let text = rawValue.precomposedStringWithCanonicalMapping
        guard !text.isEmpty else { return nil }
        self.rawValue = text
    }
}

/// One paragraph of a note: its name and its words.
public struct NoteBlock: Equatable, Sendable, Identifiable {
    public var id: BlockID
    public var text: String

    public init(id: BlockID, text: String) {
        self.id = id
        self.text = text
    }

    var isBlank: Bool { text.allSatisfy(\.isWhitespace) }
}

/// How a block ends.
public enum BlockEnding: Hashable, Sendable {
    /// The person removed the words. Their lines and every copy of them are erased.
    case deleted(BlockID)
    /// The person joined the block to another one, such as Backspace at its start. Its words live on in `into`. Nothing
    /// is erased, and a fact that quotes the block keeps its quote.
    case merged(BlockID, into: BlockID)

    var block: BlockID {
        switch self {
        case .deleted(let block), .merged(let block, _): block
        }
    }
}

/// What the editor asks the store to save: the blocks that are new or changed, the blocks that ended, and the order of
/// every block that has words.
public struct NoteChange: Equatable, Sendable {
    public var note: NoteID
    public var blocks: [NoteBlock]
    public var endings: [BlockEnding]
    public var order: [BlockID]

    public init(note: NoteID, blocks: [NoteBlock], endings: [BlockEnding], order: [BlockID]) {
        self.note = note
        self.blocks = blocks
        self.endings = endings
        self.order = order
    }
}
