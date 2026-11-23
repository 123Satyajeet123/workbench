import Foundation
import GRDB

extension Store {
    /// Notes that the source deleted these messages of one chat for good. A note already there stays as it is.
    public func noteRevokes(kind: SourceKind, label: String, messageRefs: [String]) throws {
        let grant = Self.grantID(kind: kind, label: label)
        try writer.write { db in
            for ref in messageRefs {
                try db.execute(
                    sql: "INSERT OR IGNORE INTO pending_revoke(grant_id, message_ref, at) VALUES (?,?,?)",
                    arguments: [grant, ref, clock().millisecondsSince1970])
            }
        }
    }

    /// The noted deletions of one consent kind, by chat label.
    public func pendingRevokes(kind: SourceKind) throws -> [String: [String]] {
        let prefix = Self.grantID(kind: kind, label: "")
        let rows = try writer.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT grant_id, message_ref FROM pending_revoke WHERE substr(grant_id, 1, ?) = ? ORDER BY at",
                arguments: [prefix.count, prefix])
        }
        return Dictionary(grouping: rows, by: { String(($0["grant_id"] as String).dropFirst(prefix.count)) })
            .mapValues { $0.map { $0["message_ref"] } }
    }

    /// Takes the notes away once their erase is written, or once the chat has nothing stored.
    public func clearRevokes(kind: SourceKind, label: String, messageRefs: [String]) throws {
        let grant = Self.grantID(kind: kind, label: label)
        try writer.write { db in
            for ref in messageRefs {
                try db.execute(
                    sql: "DELETE FROM pending_revoke WHERE grant_id = ? AND message_ref = ?", arguments: [grant, ref])
            }
        }
    }
}
