import Foundation

/// One piece of a PDF attachment ("type": "mail_deck"). A message to the host is at most `NativeMessage.maximumLength`
/// bytes, so a deck travels in chunks of `size` bytes, each in base64.
public struct DeckChunk: Codable, Sendable, Equatable {
    public var type = "mail_deck"
    public var context: MailContext
    public var name: String
    /// Counts from 0.
    public var index: Int
    public var count: Int
    public var data: String

    public init(context: MailContext, name: String, index: Int, count: Int, data: String) {
        self.context = context
        self.name = name
        self.index = index
        self.count = count
        self.data = data
    }

    /// Bytes of a deck in one chunk. Their base64 form and its envelope stay under the frame limit.
    public static let size = 512 * 1024
    /// Chunks of one deck at most, so a deck is at most 32 MiB.
    public static let maximumCount = 64
}

/// Chunks that have come in and are not yet a whole deck. A deck is complete when every index of its count is here.
public final class DeckAssembly {
    struct Key: Hashable {
        let messageID: String
        let name: String
    }

    /// Decks being assembled at once, at most; the oldest goes when another starts.
    static let maximumPending = 4

    private var pieces: [Key: [Int: Data]] = [:]
    private var order: [Key] = []

    public init() {}

    /// The whole deck once its last chunk is in; nil while chunks are missing or when the chunk is not valid.
    func add(_ chunk: DeckChunk) -> Data? {
        guard (1...DeckChunk.maximumCount).contains(chunk.count), (0..<chunk.count).contains(chunk.index),
            let bytes = Data(base64Encoded: chunk.data)
        else { return nil }
        let key = Key(messageID: chunk.context.messageId, name: chunk.name)
        if pieces[key] == nil {
            order.append(key)
            if order.count > Self.maximumPending { pieces[order.removeFirst()] = nil }
        }
        pieces[key, default: [:]][chunk.index] = bytes
        guard pieces[key]?.count == chunk.count else { return nil }
        let deck = (0..<chunk.count).reduce(into: Data()) { $0 += pieces[key]?[$1] ?? Data() }
        pieces[key] = nil
        order.removeAll { $0 == key }
        return deck
    }
}
