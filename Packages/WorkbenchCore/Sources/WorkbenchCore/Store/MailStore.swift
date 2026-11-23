import Foundation
import GRDB
import Lines

extension Store {
    /// Counts the thread as opened on today's work day, once per day. It holds no text.
    func noteMailOpened(thread: String, label: String) throws {
        let day = WorkDay(containing: clock()).description
        try writer.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO mail_open(thread_id, day, label) VALUES (?,?,?)",
                arguments: [thread, day, label])
        }
    }
}

extension Queries {
    private static let mailGrants = "substr(e.grant_id, 1, length(?)) = ?"
    private static let current = """
        e.id = (SELECT v.id FROM evidence v WHERE v.entity_key = e.entity_key ORDER BY v.last_seen DESC, v.id DESC LIMIT 1)
        """

    /// The mail lines sent in `start..<end`, oldest first: the current version of each message and deck page. A line's
    /// time is its message's own sent date; a message the page gave no date for is dated by when it was first seen.
    public func mailParts(from start: Date, to end: Date) throws -> [MailPart] {
        try reader.read { db in
            try StoredLine.fetchAll(
                db,
                sql: """
                    SELECT e.id AS number, \(StoredLine.columns) FROM evidence e
                    WHERE \(Self.mailGrants) AND e.event_time >= ? AND e.event_time < ? AND \(Self.current)
                    ORDER BY e.id
                    """, arguments: Self.mailPrefix + [start.millisecondsSince1970, end.millisecondsSince1970]
            ).compactMap(MailPart.init)
        }
    }

    private static var mailPrefix: StatementArguments {
        let prefix = Store.grantID(kind: .mail, label: "")
        return [prefix, prefix]
    }

    /// The facts the deck pages of a stored message share, or nil when the host kept no line of it.
    func mailMessage(thread: String, message: String) throws -> StoredMessage? {
        guard let key = try? MailLineKey.message(thread: thread, message: message) else { return nil }
        return try reader.read { db in
            try Row.fetchOne(
                db,
                sql: """
                    SELECT grant_id, actor, event_time, audience_digest FROM evidence WHERE entity_key = ?
                        ORDER BY last_seen DESC, id DESC LIMIT 1
                    """, arguments: [Data(key.bytes)]
            ).map {
                StoredMessage(
                    grantID: $0["grant_id"], actor: $0["actor"], eventTime: $0["event_time"],
                    audience: $0["audience_digest"])
            }
        }
    }

    /// Every stored line of the thread a mail item cites, in order: the messages and the deck pages the model read. The
    /// item's cited number names a line through the window of the run that made it, or, for an item made before runs kept
    /// their windows, through the old citation id. Empty when the item is not a mail item or its lines were erased.
    public func threadParts(ofItem id: Int64) throws -> [MailPart] {
        try reader.read { db in
            guard
                let thread = try String.fetchOne(
                    db,
                    sql: """
                        SELECT e.container FROM item JOIN run_window w ON w.run_id = item.run_id
                            AND w.ordinal = item.cite_first JOIN evidence e ON e.line_id = w.line_id
                        WHERE item.id = ? AND item.source = 'mail'
                        UNION
                        SELECT e.container FROM item JOIN evidence_legacy l ON l.space = ? AND l.ref = item.cite_first
                            JOIN evidence e ON e.line_id = l.line_id
                        WHERE item.id = ? AND item.source = 'mail'
                            AND NOT EXISTS (SELECT 1 FROM run_window WHERE run_id = item.run_id)
                        """, arguments: [id, LegacySpace.mailPart.rawValue, id])
            else { return [] }
            return try StoredLine.fetchAll(
                db,
                sql: """
                    SELECT e.id AS number, \(StoredLine.columns) FROM evidence e
                    WHERE e.container = ? AND \(Self.mailGrants) AND \(Self.current) ORDER BY e.id
                    """, arguments: [thread] + Self.mailPrefix
            ).compactMap(MailPart.init)
        }
    }

    public func deckNames(ofMessage messageID: String) throws -> Set<String> {
        try reader.read { db in
            Set(
                try String.fetchAll(
                    db,
                    sql: """
                        SELECT DISTINCT json_extract(coordinate, '$.file') FROM evidence
                        WHERE message_ref = ? AND coordinate IS NOT NULL
                        """, arguments: [messageID]))
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
