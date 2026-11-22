import Foundation

public struct MailPart: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case message, deck
    }

    public var id: Int64?
    public var threadID: String
    public var messageID: String
    public var kind: Kind
    public var name: String
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
