import Foundation
import GRDB

/// The watch on a passed deal: a dated fact the investor asked for when they passed ("Revisit Bolt Pay: passed for no
/// revenue; anything new?"). It is a typed fact with a due day in the item lifecycle, so Today lists it on that day
/// and not before, and Done closes it. No second reminder system exists.
public enum Revisit {
    public static let task = "vc.revisits"
    public static let lifecycle = HelperSpec.Lifecycle(field: "kind", open: ["revisit"], outcomes: ["done", "dropped"])
    /// The field of a revisit that names its deal.
    public static let dealField = "deal"
    /// How long after a pass the revisit falls due, unless the investor sets another day.
    public static let defaultMonths = 6
    static let dropped = "dropped"

    public static func defaultDay(after pass: Date, calendar: Calendar = .current) -> WorkDay {
        WorkDay(
            containing: calendar.date(byAdding: .month, value: defaultMonths, to: pass) ?? pass, calendar: calendar)
    }

    /// What Today says on the day.
    public static func line(company: String, reason: String?) -> String {
        "Revisit \(company): passed\(reason.map { " for \($0)" } ?? ""); anything new?"
    }
}

extension Store {
    /// Sets the one revisit of a passed deal, replacing an open one. The investor typed it, so it is a fact of the kind
    /// `typed` with no run. Today lists it from its due day on.
    @discardableResult
    public func setRevisit(of deal: WorkObject, on due: WorkDay, reason: String?) throws -> Int64 {
        let now = clock()
        let reason = reason?.cleaned
        let line = Revisit.line(company: deal.title, reason: reason)
        let fields = [
            "kind": "revisit", Revisit.dealField: deal.id, "company": deal.title, "why": reason ?? "",
            "eta": due.description, "text": line, "asks": "",
        ]
        return try writer.write { db in
            try dropRevisits(of: deal.id, db)
            try db.execute(
                sql: """
                    INSERT INTO item(task, day, scope, source, cite_first, cite_last, start_at, end_at, fields, quote,
                        created_at, authority) VALUES (?,?,?,?,0,0,?,?,?,?,?,?)
                    """,
                arguments: [
                    Revisit.task, WorkDay(containing: now).description, "", SourceKind.typed.rawValue, now.stored,
                    now.stored, try Coding.json(fields), line, now.stored, Authority.ownWords.rawValue,
                ])
            return db.lastInsertedRowID
        }
    }

    /// Closes the open revisit of a deal as dropped: the deal came back from Rejected.
    public func dropRevisits(of deal: String) throws {
        try writer.write { db in try dropRevisits(of: deal, db) }
    }

    private func dropRevisits(of deal: String, _ db: Database) throws {
        for id in try Queries.revisits(db, of: deal).filter({ $0.closed == nil }).compactMap(\.id) {
            try addEvent(db, item: id, kind: .close, outcome: Revisit.dropped, at: clock())
        }
    }
}

extension Queries {
    /// The revisits of one deal, or of every deal, open and closed, oldest first.
    public func revisits(of deal: String? = nil) throws -> [Item] {
        try reader.read { db in try Self.revisits(db, of: deal) }
    }

    /// The revisits still open, as of `day` when given.
    public func openRevisits(asOf day: WorkDay? = nil) throws -> [Item] {
        try openItems(of: Revisit.task, lifecycle: Revisit.lifecycle, asOf: day)
    }

    static func revisits(_ db: Database, of deal: String?) throws -> [Item] {
        try db.fetch(
            "item",
            """
            SELECT \(itemColumns) FROM \(itemRows)
            WHERE task = ? AND (? IS NULL OR json_extract(fields, '$.deal') = ?) ORDER BY id
            """, [Revisit.task, deal, deal], as: Item.init(row:))
    }

    /// The news signals about one company, or about every company, from `day` on, newest first.
    public func newsSignals(of company: String? = nil, since day: WorkDay? = nil) throws -> [Item] {
        try reader.read { db in
            try db.fetch(
                "item",
                """
                SELECT \(Self.itemColumns) FROM \(Self.itemRows)
                WHERE \(NewsSignals.ownTasks) AND (? IS NULL OR json_extract(fields, '$.company_id') = ?)
                    AND day >= ?
                ORDER BY day DESC, id DESC
                """,
                StatementArguments(NewsSignals.ownTasksArguments)
                    + [company, company, day?.description ?? "0000-00-00"], as: Item.init(row:))
        }
    }
}
