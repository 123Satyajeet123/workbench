import Foundation
import GRDB

extension Store {
    /// Keeps the lines a tool returned in the window of the run, in the transaction of the read, and gives each its
    /// number there. A line the window already holds keeps its number. A new line takes the next number.
    static func trace(_ lines: [StoredLine], in run: RunID, _ db: Database) throws -> [Data: Int] {
        var numbers: [Data: Int] = [:]
        for line in lines where numbers[line.lineID] == nil {
            numbers[line.lineID] = try number(of: line.lineID, in: run, db)
        }
        return numbers
    }

    private static func number(of lineID: Data, in run: RunID, _ db: Database) throws -> Int {
        if let held = try Int.fetchOne(
            db, sql: "SELECT MIN(ordinal) FROM run_window WHERE run_id = ? AND line_id = ?", arguments: [run, lineID])
        {
            return held
        }
        let next =
            try Int.fetchOne(
                db, sql: "SELECT COALESCE(MAX(ordinal), 0) + 1 FROM run_window WHERE run_id = ?", arguments: [run])
            ?? 1
        try db.execute(
            sql: "INSERT INTO run_window(run_id, ordinal, line_id) VALUES (?,?,?)", arguments: [run, next, lineID])
        return next
    }
}
