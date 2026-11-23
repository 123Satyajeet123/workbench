import Foundation
import Lines

/// The people of one Gmail message, as the page showed them in attributes. Addresses are trimmed, lower case and NFC, so
/// the same person has one id however the page spelled it.
struct MailPeople: Equatable {
    let sender: String
    let recipients: [String]
    let account: String?

    init(sender: String, recipients: [String], account: String?) {
        self.sender = Self.canonical(sender)
        self.recipients = recipients.map(Self.canonical).filter { !$0.isEmpty }
        self.account = account.map(Self.canonical).flatMap { $0.isEmpty ? nil : $0 }
    }

    static func canonical(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().precomposedStringWithCanonicalMapping
    }

    /// `me` for mail from the person's own account, else the sender's address. Nil when the page showed no sender: the
    /// authority of the line is then unknown.
    var actor: String? {
        guard !sender.isEmpty else { return nil }
        return sender == account ? WhatsAppAudience.owner : sender
    }

    /// Who could read the message: the owner, the sender and everyone it went to. Nil when the page showed no sender or
    /// no recipient, because then nobody can say who could read it.
    func audience(thread: String) -> AudienceDigest? {
        guard !sender.isEmpty, !recipients.isEmpty else { return nil }
        let container = Container(id: thread, kind: .group, title: "")
        return AudienceRule.digest(
            of: container, owner: WhatsAppAudience.owner,
            membership: Membership(members: [sender] + recipients, proof: .pageAttributes))
    }
}

/// How a Gmail line is named: by the site, the thread and the message id the page gave. A deck page adds its file and
/// page to the message id.
enum MailLineKey {
    static func message(thread: String, message: String) throws(EntityKeyError) -> EntityKey {
        try EntityKey.web(site: MailContext.site, container: thread, itemID: message)
    }

    static func deckPage(thread: String, message: String, file: String, page: Int) throws(EntityKeyError)
        -> EntityKey
    {
        try self.message(thread: thread, message: "\(message)/\(file)/\(page)")
    }
}

enum MailReader {
    static let version = "gmail-dom 1"
}

extension MailMessage {
    /// What one message gives the evidence store, or nil when no line may be written: the grant names no label, the page
    /// gave no thread or message id, no text, or not the sender and the recipients. The label is the grant's.
    func reading(grant: CaptureGrant, now: Date) -> SourceReading? {
        let people = MailPeople(sender: sender, recipients: recipients, account: account)
        guard let label = grant.label, !label.isEmpty, let audience = people.audience(thread: context.threadId)
        else { return nil }
        let time = UTCInstant(sent.map(Date.init(timeIntervalSince1970:)) ?? now)
        func line(_ words: String, id: String, forwarded: Bool) -> ObservedLine? {
            guard !words.isEmpty, let key = try? MailLineKey.message(thread: context.threadId, message: id) else {
                return nil
            }
            return ObservedLine(
                line: Line(
                    entity: key, text: String(words.prefix(Self.maximumCharacters)), readerVersion: MailReader.version),
                eventTime: time, actor: people.actor, messageRef: context.messageId, forwarded: forwarded)
        }
        let lines = [
            line(text, id: context.messageId, forwarded: false),
            line(quoted ?? "", id: "\(context.messageId)/quoted", forwarded: true),
        ].compactMap { $0 }
        guard !lines.isEmpty else { return nil }
        return SourceReading(
            grant: grant, label: label, container: context.threadId, audience: audience, lines: lines,
            cursorAfter: nil, readerVersion: MailReader.version)
    }
}

/// What the store kept of a message line, which the deck pages of that message share.
struct StoredMessage: Equatable {
    var grantID: String
    var actor: String?
    var eventTime: Int64?
    var audience: Data
}

extension StoredMessage {
    /// The pages of a deck as lines under this message: its audience and sender, the file and page of each.
    func reading(
        pages: [(page: Int, text: String)], file: String, thread: String, message: String, grant: CaptureGrant
    ) -> SourceReading? {
        guard let label = grant.label, let audience = AudienceDigest(bytes: Array(audience)) else { return nil }
        let lines: [ObservedLine] = pages.compactMap { page in
            guard let key = try? MailLineKey.deckPage(thread: thread, message: message, file: file, page: page.page),
                let place = try? Coding.json(MailPlace(file: file, page: page.page))
            else { return nil }
            return ObservedLine(
                line: Line(entity: key, text: page.text, readerVersion: MailReader.version),
                eventTime: eventTime.map(UTCInstant.init(milliseconds:)), actor: actor, messageRef: message,
                coordinate: place)
        }
        guard !lines.isEmpty else { return nil }
        return SourceReading(
            grant: grant, label: label, container: thread, audience: audience, lines: lines, cursorAfter: nil,
            readerVersion: MailReader.version)
    }
}
