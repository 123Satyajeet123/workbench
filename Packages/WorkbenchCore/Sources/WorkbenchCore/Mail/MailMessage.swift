import Foundation

/// Where in Gmail the extension read something: one message of one thread, opened inside one label.
public struct MailContext: Codable, Sendable, Equatable {
    /// The browser's bundle id. The app sets it from the process that sent the message, never from the message.
    public var browser = ""
    /// The address of the Gmail tab.
    public var url: String
    public var label: String
    public var threadId: String
    public var messageId: String

    private enum CodingKeys: String, CodingKey { case url, label, threadId, messageId }

    public init(browser: String, url: String, label: String, threadId: String, messageId: String) {
        self.browser = browser
        self.url = url
        self.label = label
        self.threadId = threadId
        self.messageId = messageId
    }

    /// The only site mail is read on.
    public static let site = "mail.google.com"

    /// A grant to keep mail of this label, or nil: mail is off, the label is not the named one, or the tab is not Gmail
    /// in a known browser.
    func grant(policy: CapturePolicy, at now: Date) -> CaptureGrant? {
        guard CapturePolicy.browserBundleIDs.contains(browser), CapturePolicy.isSite(url, in: [Self.site]) else {
            return nil
        }
        return policy.authorize(CaptureRequest(kind: .mail, label: label), at: now).grant
    }
}

/// The text of one expanded message, sent by the extension while the thread is open ("type": "mail"). The addresses
/// come from attributes of the page, never from its text.
public struct MailMessage: Codable, Sendable, Equatable {
    public var type = "mail"
    public var context: MailContext
    /// The address of the sender.
    public var sender: String
    /// The addresses the message went to, to and cc: empty when the page did not show them.
    public var recipients: [String]
    /// The address of the Gmail account the page is open for, when the page names it.
    public var account: String?
    /// Seconds since 1970 when the page showed the message's date; nil when it could not be read.
    public var sent: Double?
    public var text: String
    /// The text of the blocks the page marks as quoted from an earlier message; nil or empty when it marks none.
    public var quoted: String?
    /// The file names of PDF attachments the page lists, so the host can say which decks it still lacks.
    public var attachments: [String]

    public init(
        context: MailContext, sender: String, recipients: [String] = [], account: String? = nil, sent: Double? = nil,
        text: String, quoted: String? = nil, attachments: [String] = []
    ) {
        self.context = context
        self.sender = sender
        self.recipients = recipients
        self.account = account
        self.sent = sent
        self.text = text
        self.quoted = quoted
        self.attachments = attachments
    }

    /// Characters of one message kept at most.
    public static let maximumCharacters = 100_000
}
