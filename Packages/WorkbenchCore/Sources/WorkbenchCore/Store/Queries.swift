import Foundation
import GRDB

public struct Queries: Sendable {
    let reader: any DatabaseReader
    let directory: URL

    public func policy() throws -> CapturePolicy {
        let latest = try reader.read { db in
            try String.fetchOne(db, sql: "SELECT policy FROM consent ORDER BY id DESC LIMIT 1")
        }
        guard let json = latest else { return CapturePolicy() }
        return try Coding.value(CapturePolicy.self, from: json)
    }

    public func state(forKey key: String) throws -> String? {
        try reader.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM state WHERE key = ?", arguments: [key])
        }
    }

    public func activities(since start: Date) throws -> [Activity] {
        try activities(from: start, to: .distantFuture)
    }

    public func activities(from start: Date, to end: Date) throws -> [Activity] {
        try reader.read { db in
            try db.fetch(
                "activity",
                "SELECT id, ts, kind, app, bundle_id, title, document, text FROM activity WHERE ts >= ? AND ts < ? ORDER BY id",
                [start.stored, end.stored], as: Activity.init(row:))
        }
    }

    public func count(of table: Table) throws -> Int {
        try reader.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table.rawValue)") ?? 0 }
    }

    public enum Table: String, CaseIterable, Sendable {
        case state, consent, run, activity, recording
        case prompt, item, mark, team, member, machine, proposal
    }
}

extension Activity {
    init(row: Row) throws {
        self.init(
            id: try row.optionalValue("id"), at: try row.date("ts"), kind: try row.enumeration("kind"),
            app: try row.value("app"), bundleID: try row.value("bundle_id"), title: try row.value("title"),
            document: try row.optionalValue("document"), text: try row.optionalValue("text"))
    }
}
