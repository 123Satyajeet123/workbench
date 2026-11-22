import Foundation

public struct DeckChunk: Codable, Sendable, Equatable {
    public var type = "mail_deck"
    public var context: MailContext
    public var name: String
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

    public static let size = 512 * 1024
    public static let maximumCount = 64
}

public final class DeckAssembly {
    struct Key: Hashable {
        let messageID: String
        let name: String
    }

    static let maximumPending = 4

    private var pieces: [Key: [Int: Data]] = [:]
    private var order: [Key] = []

    public init() {}

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
