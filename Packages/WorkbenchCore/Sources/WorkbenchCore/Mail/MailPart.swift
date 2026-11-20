import Foundation

/// One piece of a Gmail thread the person opened: a message, or one page of a deck attached to a message. Every
/// part is kept once per message, and only for a label the person named.
public struct MailPart: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case message, deck
    }

    /// Set when read from the store.
    public var id: Int64?
    public var threadID: String
    public var messageID: String
    public var kind: Kind
    /// The attached file of a deck page; empty for a message.
    public var name: String
    /// Counts from 1 for a deck page; 0 for a message.
    public var page: Int
    public var label: String
    public var sender: String
    public var subject: String
    public var sentAt: Date
    public var seenAt: Date
    public var text: String

    public init(
        id: Int64? = nil, threadID: String, messageID: String, kind: Kind = .message, name: String = "",
        page: Int = 0, label: String, sender: String, subject: String, sentAt: Date, seenAt: Date, text: String
    ) {
        self.id = id
        self.threadID = threadID
        self.messageID = messageID
        self.kind = kind
        self.name = name
        self.page = page
        self.label = label
        self.sender = sender
        self.subject = subject
        self.sentAt = sentAt
        self.seenAt = seenAt
        self.text = text
    }
}

/// Parts the policy allowed to keep, with the thread they belong to. Only this module can make one.
public struct MailBatch: Sendable, Equatable {
    public let parts: [MailPart]
    public let threadID: String
    public let label: String
    let grant: CaptureGrant

    init?(_ parts: [MailPart], threadID: String, label: String, grant: CaptureGrant) {
        guard !parts.isEmpty else { return nil }
        self.parts = parts
        self.threadID = threadID
        self.label = label
        self.grant = grant
    }
}
