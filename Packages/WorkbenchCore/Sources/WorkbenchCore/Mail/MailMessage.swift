import Foundation

public struct MailContext: Codable, Sendable, Equatable {
    public var browser: String
    public var url: String
    public var label: String
    public var threadId: String
    public var messageId: String

    public init(browser: String, url: String, label: String, threadId: String, messageId: String) {
        self.browser = browser
        self.url = url
        self.label = label
        self.threadId = threadId
        self.messageId = messageId
    }

    public static let site = "mail.google.com"

    func grant(policy: CapturePolicy, at now: Date) -> CaptureGrant? {
        guard CapturePolicy.browserBundleIDs.contains(browser), CapturePolicy.isSite(url, in: [Self.site]) else {
            return nil
        }
        return policy.authorize(CaptureRequest(kind: .mail, label: label), at: now).grant
    }
}

public struct MailMessage: Codable, Sendable, Equatable {
    public var type = "mail"
    public var context: MailContext
    public var sender: String
    public var subject: String
    public var sent: Double?
    public var text: String
    public var attachments: [String]

    public init(
        context: MailContext, sender: String, subject: String, sent: Double? = nil, text: String,
        attachments: [String] = []
    ) {
        self.context = context
        self.sender = sender
        self.subject = subject
        self.sent = sent
        self.text = text
        self.attachments = attachments
    }

    public static let maximumCharacters = 100_000

    func batch(policy: CapturePolicy, at now: Date) -> MailBatch? {
        guard let grant = context.grant(policy: policy, at: now), !text.isEmpty else { return nil }
        let part = MailPart(
            threadID: context.threadId, messageID: context.messageId, label: context.label, sender: sender,
            subject: subject, sentAt: sent.map(Date.init(timeIntervalSince1970:)) ?? now, seenAt: now,
            text: String(text.prefix(Self.maximumCharacters)))
        return MailBatch([part], threadID: context.threadId, label: context.label, grant: grant)
    }
}
