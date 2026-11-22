import Foundation

enum MailIntake {
    static func status(store: Store) throws -> PageHost.Reply {
        let policy = try store.currentPolicy()
        let now = store.clock()
        let labels = (policy.allowList[.mail] ?? []).sorted().filter {
            policy.authorize(CaptureRequest(kind: .mail, label: $0), at: now).grant != nil
        }
        return PageHost.Reply(kept: false, labels: labels)
    }

    static func keep(_ message: MailMessage, store: Store) throws -> PageHost.Reply {
        guard let batch = message.batch(policy: try store.currentPolicy(), at: store.clock()) else {
            return PageHost.Reply(kept: false)
        }
        let added = try store.record(batch)
        let known = try store.queries.deckNames(ofMessage: message.context.messageId)
        return PageHost.Reply(kept: added > 0, wantDecks: message.attachments.filter { !known.contains($0) })
    }

    static func keep(_ chunk: DeckChunk, decks: DeckAssembly, store: Store) throws -> PageHost.Reply {
        let now = store.clock()
        guard let grant = chunk.context.grant(policy: try store.currentPolicy(), at: now),
            let message = try store.queries.mailMessage(id: chunk.context.messageId),
            message.label == chunk.context.label, let deck = decks.add(chunk)
        else { return PageHost.Reply(kept: false) }
        let parts = DeckText.pages(in: deck).map { page in
            MailPart(
                threadID: message.threadID, messageID: message.messageID, kind: .deck, name: chunk.name,
                page: page.page, label: message.label, sender: message.sender, subject: message.subject,
                sentAt: message.sentAt, seenAt: now, text: page.text)
        }
        guard let batch = MailBatch(parts, threadID: message.threadID, label: message.label, grant: grant) else {
            return PageHost.Reply(kept: false)
        }
        return PageHost.Reply(kept: try store.record(batch) > 0)
    }
}
