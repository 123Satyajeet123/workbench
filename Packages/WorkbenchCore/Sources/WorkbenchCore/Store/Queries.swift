import Foundation

/// Every read. Reads need no actor: the database handle locks itself.
public struct Queries: Sendable {
    let database: Database
    let directory: URL

    /// The latest consent. A store with none yet has the default policy.
    public func policy() throws -> CapturePolicy {
        guard let json = try database.rows("SELECT policy FROM consent ORDER BY id DESC LIMIT 1").first?[0].string
        else { return CapturePolicy() }
        return try Coding.value(CapturePolicy.self, from: json)
    }

    public func state(forKey key: String) throws -> String? {
        try database.rows("SELECT value FROM state WHERE key = ?", [.text(key)]).first?[0].string
    }

    public func activities(since start: Date) throws -> [Activity] {
        try activities(from: start, to: .distantFuture)
    }

    /// Activity in `start..<end`, oldest first.
    public func activities(from start: Date, to end: Date) throws -> [Activity] {
        try database.rows(
            "SELECT id, ts, kind, app, bundle_id, title, document, text FROM activity WHERE ts >= ? AND ts < ? ORDER BY id",
            [SQLValue(start), SQLValue(end)]
        )
        .compactMap { row in
            guard let kind = row[2].string.flatMap(Activity.Kind.init) else { return nil }
            return Activity(
                id: row[0].integer, at: row[1].date ?? .distantPast, kind: kind, app: row[3].string ?? "",
                bundleID: row[4].string ?? "", title: row[5].string ?? "", document: row[6].string,
                text: row[7].string)
        }
    }

    public func count(of table: Table) throws -> Int {
        Int(try database.rows("SELECT COUNT(*) FROM \(table.rawValue)").first?[0].integer ?? 0)
    }

    public enum Table: String, CaseIterable, Sendable {
        case state, consent, run, activity, recording
        case prompt, item, mark, team, member, machine
    }
}
