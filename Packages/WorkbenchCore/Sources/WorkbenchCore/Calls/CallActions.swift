import Foundation
import GRDB

public enum CallAction {
    public static let task = "call.actions"
    public static let lifecycle = HelperSpec.Lifecycle(
        field: "kind", open: ["commitment"], outcomes: ["done", "dropped"])
    public static let callField = "call"
    static let dropped = "dropped"
}

extension Store {
    @discardableResult
    public func saveCallActions(
        of recording: Recording, lines: [CallLine], summary: CallSummary, founder: String, run: RunID
    ) throws -> [Int64] {
        let now = clock()
        let call = recording.source.label
        return try writer.write { db in
            try dropCallActions(of: recording.id, db)
            return try summary.actions.compactMap { action -> Int64? in
                guard let text = action.text.cleaned, let quote = action.quote.cleaned,
                    let line = lines.first(where: { $0.text.contains(quote: quote) })
                else { return nil }
                let said = recording.startedAt.addingTimeInterval(line.start)
                let fields = [
                    "kind": "commitment", "person": action.owner, "project": call, "text": text,
                    "eta": WorkDay(action.due)?.description ?? "",
                    "asks": Self.isFounder(action.owner, founder) ? "founder" : "team", "stance": "said",
                    CallAction.callField: String(recording.id),
                ]
                return try Self.insertItem(
                    db, task: CallAction.task, run: run, day: WorkDay(containing: recording.startedAt),
                    scope: String(recording.id), source: .call, cite: (0, 0), span: (said, said), fields: fields,
                    quote: quote, at: now)
            }
        }
    }

    public func dropCallActions(of recording: Int64) throws {
        try writer.write { db in try dropCallActions(of: recording, db) }
    }

    private func dropCallActions(of recording: Int64, _ db: Database) throws {
        let open = try Queries.callActions(db, of: recording).filter { $0.closed == nil }
        for id in open.compactMap(\.id) {
            try addEvent(db, item: id, kind: "close", outcome: CallAction.dropped, at: clock())
        }
    }

    static func isFounder(_ owner: String, _ founder: String) -> Bool {
        let owner = owner.comparable
        guard !owner.isEmpty else { return false }
        let name = founder.replacingOccurrences(of: " (You)", with: "").comparable
        return owner == founder.comparable || owner == name || owner == "you"
    }
}

extension Queries {
    public func openCallActions(asOf day: WorkDay? = nil) throws -> [Item] {
        try openItems(of: CallAction.task, lifecycle: CallAction.lifecycle, asOf: day)
    }

    public func callActions(of recording: Int64? = nil) throws -> [Item] {
        try reader.read { db in try Self.callActions(db, of: recording) }
    }

    static func callActions(_ db: Database, of recording: Int64?) throws -> [Item] {
        try db.fetch(
            "item",
            """
            SELECT \(itemColumns) FROM \(itemRows)
            WHERE task = ? AND (? IS NULL OR scope = ?) ORDER BY id
            """, [CallAction.task, recording.map(String.init), recording.map(String.init)], as: Item.init(row:))
    }
}
