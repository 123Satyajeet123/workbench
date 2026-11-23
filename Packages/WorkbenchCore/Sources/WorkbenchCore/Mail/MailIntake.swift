import Foundation
import Kernel

/// The native host's work for mail messages. Each step asks the capture policy itself: mail that is switched off, in
/// another label than the named one, or not from Gmail is dropped here, whatever the extension sent. Lines go to the
/// evidence store through its one writer, which checks the consent again inside its write transaction.
enum MailIntake {
    /// The labels the extension may read now: those the policy allows for mail. Empty when mail is off.
    static func status(store: Store) throws -> PageHost.Reply {
        let policy = try store.currentPolicy()
        let now = store.clock()
        let labels = (policy.allowList[.mail] ?? []).sorted().filter {
            policy.authorize(CaptureRequest(kind: .mail, label: $0), at: now).grant != nil
        }
        return PageHost.Reply(kept: false, labels: labels)
    }

    /// Keeps a message the policy allows, and names the attached decks the host does not have yet. A message whose page
    /// did not show who sent it and who it went to is not kept.
    static func keep(_ message: MailMessage, store: Store, owner: PersonID) throws -> PageHost.Reply {
        guard let grant = message.context.grant(policy: try store.currentPolicy(), at: store.clock()),
            let reading = message.reading(grant: grant, now: store.clock())
        else { return PageHost.Reply(kept: false) }
        let report = try store.record(reading, of: .gmailMail, owner: owner)
        try store.noteMailOpened(thread: message.context.threadId, label: reading.label)
        let known = try store.queries.deckNames(ofMessage: message.context.messageId)
        return PageHost.Reply(
            kept: report.inserted > 0, wantDecks: message.attachments.filter { !known.contains($0) })
    }

    /// Adds a chunk of a deck. When the deck is whole, keeps the text of its pages under the stored message.
    static func keep(_ chunk: DeckChunk, decks: DeckAssembly, store: Store, owner: PersonID) throws -> PageHost.Reply {
        let context = chunk.context
        guard let grant = context.grant(policy: try store.currentPolicy(), at: store.clock()),
            let message = try store.queries.mailMessage(thread: context.threadId, message: context.messageId),
            message.grantID == Store.grantID(kind: .mail, label: context.label), let deck = decks.add(chunk),
            let reading = message.reading(
                pages: DeckText.pages(in: deck), file: chunk.name, thread: context.threadId,
                message: context.messageId, grant: grant)
        else { return PageHost.Reply(kept: false) }
        return PageHost.Reply(kept: try store.record(reading, of: .gmailMail, owner: owner).inserted > 0)
    }
}
