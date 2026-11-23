import Foundation
import GRDB

/// A fact that passed the audience check, with the stored lines it cites.
struct AdmittedFact {
    let item: Item
    let title: String
    let cites: [StoredLine]

    func found(numbers: [Data: Int]) throws -> FoundFact {
        FoundFact(
            item: item.id ?? 0, task: item.task, title: title, fields: item.fields,
            state: item.closed?.outcome ?? "open",
            cites: try cites.map { try FoundLine($0, number: numbers[$0.lineID] ?? 0) })
    }
}

extension Store {
    static func admittedFacts(
        matching match: String, _ filter: FactFilter, limit: Int, audience: ReaderAudience, in db: Database
    ) throws -> [AdmittedFact] {
        let rows = try Row.fetchCursor(db, sql: factSearch(filter), arguments: try factSearchArguments(match, filter))
        var titleFields: [String: String] = [:]
        var admitted: [AdmittedFact] = []
        while admitted.count < limit, let row = try rows.next() {
            let item = try Item(row: row)
            guard let cites = try admittedCites(of: item, audience: audience, in: db) else { continue }
            if titleFields[item.task] == nil { titleFields[item.task] = try titleField(ofTask: item.task, in: db) }
            admitted.append(AdmittedFact(item: item, title: item[titleFields[item.task] ?? ""], cites: cites))
        }
        return admitted
    }

    /// The lines the fact cites, or nil when the fact must not be shown: a cited line is gone, was deleted at its
    /// source, or the reader may not read it. A fact that cites no line has none to refuse.
    private static func admittedCites(of item: Item, audience: ReaderAudience, in db: Database) throws -> [StoredLine]?
    {
        let cites = try Queries.proofLines(of: item, reach: 0, in: db).filter(\.isCited).map(\.line)
        let citesSomething = item.citeFirst > 0
        guard !(citesSomething && cites.isEmpty) else { return nil }
        return cites.allSatisfy({ !$0.isTombstone && audience.admits($0) }) ? cites : nil
    }

    private static func titleField(ofTask task: String, in db: Database) throws -> String {
        try machineSpec(ofTask: Trial.machineTask(of: task), in: db)?.title ?? ""
    }

    private static func factSearch(_ filter: FactFilter) -> String {
        """
        SELECT \(Queries.itemColumns) FROM item_fts, \(Queries.itemRows)
        WHERE item_fts MATCH ? AND item_mark.id = item_fts.rowid AND item_mark.source_deleted = 0
            AND (? IS NULL OR item_mark.task IN (SELECT value FROM json_each(?)))
            AND (? = 0 OR (item_mark.state <> 'rejected' AND (status_kind IS NULL OR status_kind = 'reopen')))
            AND (? IS NULL OR item_mark.start_at >= ?) AND (? IS NULL OR item_mark.start_at < ?)
        ORDER BY bm25(item_fts), item_mark.start_at DESC, item_mark.id DESC
        """
    }

    private static func factSearchArguments(_ match: String, _ filter: FactFilter) throws -> StatementArguments {
        let tasks = try filter.tasks.map { try Coding.json($0) }
        let since = filter.since?.stored
        let until = filter.until?.stored
        return [match, tasks, tasks, filter.openOnly ? 1 : 0, since, since, until, until]
    }
}
