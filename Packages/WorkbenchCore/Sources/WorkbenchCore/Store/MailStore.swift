import Foundation
import GRDB

extension Store {
    /// Keeps the parts of a batch that are new: a part whose message id (and file and page) is stored already is left
    /// out, so opening a thread twice adds nothing. The thread counts as opened on today's work day. Returns how many
    /// parts were new.
    @discardableResult
    public func record(_ batch: MailBatch) throws -> Int {
        try check(batch.grant, kind: .mail, label: batch.label)
        let day = WorkDay(containing: clock()).description
        return try writer.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO mail_open(thread_id, day, label) VALUES (?,?,?)",
                arguments: [batch.threadID, day, batch.label])
            var added = 0
            for part in batch.parts {
                try db.execute(
                    sql: """
                        INSERT OR IGNORE INTO mail_part(thread_id, message_id, kind, name, page, label, sender, subject,
                            sent_at, seen_at, text) VALUES (?,?,?,?,?,?,?,?,?,?,?)
                        """,
                    arguments: [
                        part.threadID, part.messageID, part.kind.rawValue, part.name, part.page, part.label,
                        part.sender, part.subject, part.sentAt.stored, part.seenAt.stored, part.text,
                    ])
                added += db.changesCount
            }
            return added
        }
    }
}

extension Queries {
    /// Parts first seen in `start..<end`, oldest first.
    public func mailParts(from start: Date, to end: Date) throws -> [MailPart] {
        try reader.read { db in
            try db.fetch(
                "mail_part",
                """
                SELECT id, thread_id, message_id, kind, name, page, label, sender, subject, sent_at, seen_at, text
                FROM mail_part WHERE seen_at >= ? AND seen_at < ? ORDER BY id
                """, [start.stored, end.stored], as: MailPart.init(row:))
        }
    }

    /// The stored message with this id, not a deck page.
    public func mailMessage(id messageID: String) throws -> MailPart? {
        try reader.read { db in
            try db.fetch(
                "mail_part",
                """
                SELECT id, thread_id, message_id, kind, name, page, label, sender, subject, sent_at, seen_at, text
                FROM mail_part WHERE message_id = ? AND kind = 'message'
                """, [messageID], as: MailPart.init(row:)
            ).first
        }
    }

    /// The names of the decks stored for a message.
    public func deckNames(ofMessage messageID: String) throws -> Set<String> {
        try reader.read { db in
            Set(
                try String.fetchAll(
                    db, sql: "SELECT DISTINCT name FROM mail_part WHERE message_id = ? AND kind = 'deck'",
                    arguments: [messageID]))
        }
    }

    /// How many threads of `label` were opened on each work day. Only threads opened in the browser are counted; the
    /// threads in the label that were never opened cannot be known from the page.
    public func mailThreadsOpened(inLabel label: String) throws -> [WorkDay: Int] {
        try reader.read { db in
            let rows = try Row.fetchAll(
                db, sql: "SELECT day, COUNT(*) AS threads FROM mail_open WHERE label = ? GROUP BY day",
                arguments: [label])
            return Dictionary(
                uniqueKeysWithValues: try rows.map { (try $0.workDay("day"), try $0.value("threads") as Int) })
        }
    }
}

extension MailPart {
    init(row: Row) throws {
        self.init(
            id: try row.value("id"), threadID: try row.value("thread_id"), messageID: try row.value("message_id"),
            kind: try row.enumeration("kind"), name: try row.value("name"), page: try row.value("page"),
            label: try row.value("label"), sender: try row.value("sender"), subject: try row.value("subject"),
            sentAt: try row.date("sent_at"), seenAt: try row.date("seen_at"), text: try row.value("text"))
    }
}
