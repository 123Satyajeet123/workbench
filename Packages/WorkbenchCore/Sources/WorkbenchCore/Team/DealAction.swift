import Foundation
import GRDB

/// What a deal in "Action required" waits for, such as "get the cap table from the founder, by Friday". It is an open
/// commitment fact with a due date, linked to its deal by the `deal` field. It lives in the item lifecycle, so Today
/// lists it, the derailment watch follows it, and Done closes it. No second open and close system exists.
public enum DealAction {
    public static let task = "vc.deal-actions"
    public static let lifecycle = HelperSpec.Lifecycle(
        field: "kind", open: ["commitment"], outcomes: ["done", "dropped"])
    /// The field of an action that names its deal.
    public static let dealField = "deal"
    static let done = "done"
    static let dropped = "dropped"

    /// The deals whose wait is over: in "Action required", no action open, and an action of this wait closed as
    /// done. An action closed before the deal came to this stage belongs to an earlier wait and does not count.
    public static func settled(_ deals: [WorkObject], actions: [Item]) -> [WorkObject] {
        deals.filter { deal in
            guard deal.stages == [WorkObject.actionRequired] else { return false }
            let own = actions.filter { $0[dealField] == deal.id }
            let since = deal.history.filter { deal.stageHeads.contains($0.id) }.map(\.at).max() ?? .distantPast
            return own.allSatisfy { $0.closed != nil }
                && own.contains { $0.closed?.outcome == done && ($0.closed?.at ?? .distantPast) >= since }
        }
    }
}

extension Store {
    /// Opens the one action a deal waits for, and drops one it already had: the new ask replaces it. The founder
    /// typed it, so it is a fact of the kind `typed`, with no run.
    @discardableResult
    public func requireAction(of deal: WorkObject, what: String, due: WorkDay, owner: String) throws -> Int64? {
        guard let what = what.cleaned else { return nil }
        let now = clock()
        return try writer.write { db in
            try dropActions(of: deal.id, db)
            var fields = [
                "kind": "commitment", "person": owner, "project": deal.title, "text": what, "eta": due.description,
                "stance": "said", DealAction.dealField: deal.id,
            ]
            if let asksMe = HelperSpec.Attention.builtIn.asksMe { fields[asksMe.field] = asksMe.value }
            try db.execute(
                sql: """
                    INSERT INTO item(task, day, scope, source, cite_first, cite_last, start_at, end_at, fields, quote,
                        created_at, authority) VALUES (?,?,?,?,0,0,?,?,?,?,?,?)
                    """,
                arguments: [
                    DealAction.task, WorkDay(containing: now).description, "", SourceKind.typed.rawValue,
                    now.stored, now.stored, try Coding.json(fields), what, now.stored, Authority.ownWords.rawValue,
                ])
            return db.lastInsertedRowID
        }
    }

    /// Closes the open actions of a deal as dropped: the deal left "Action required" by hand.
    public func dropActions(of deal: String) throws {
        try writer.write { db in try dropActions(of: deal, db) }
    }

    private func dropActions(of deal: String, _ db: Database) throws {
        let open = try Queries.dealActions(db, of: deal).filter { $0.closed == nil }
        for id in open.compactMap(\.id) {
            try addEvent(db, item: id, kind: .close, outcome: DealAction.dropped, at: clock())
        }
    }
}

extension Queries {
    /// The actions of one deal, or of every deal, open and closed, oldest first.
    public func dealActions(of deal: String? = nil) throws -> [Item] {
        try reader.read { db in try Self.dealActions(db, of: deal) }
    }

    /// The actions still open, as of `day` when given: what Today lists and the derailment watch follows.
    public func openDealActions(asOf day: WorkDay? = nil) throws -> [Item] {
        try openItems(of: DealAction.task, lifecycle: DealAction.lifecycle, asOf: day)
    }

    static func dealActions(_ db: Database, of deal: String?) throws -> [Item] {
        try db.fetch(
            "item",
            """
            SELECT \(itemColumns) FROM \(itemRows)
            WHERE task = ? AND (? IS NULL OR json_extract(fields, '$.deal') = ?) ORDER BY id
            """, [DealAction.task, deal, deal], as: Item.init(row:))
    }
}
