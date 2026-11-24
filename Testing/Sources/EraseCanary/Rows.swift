import Foundation
import GRDB

@testable import WorkbenchCore

extension Store {
    func rows(_ sql: String, _ arguments: StatementArguments = StatementArguments()) throws -> [Row] {
        try writer.read { db in try Row.fetchAll(db, sql: sql, arguments: arguments) }
    }

    func count(_ sql: String, _ arguments: StatementArguments = StatementArguments()) throws -> Int {
        try writer.read { db in try Int.fetchOne(db, sql: sql, arguments: arguments) ?? 0 }
    }

    /// The tables, shadow tables of the search indexes among them, that hold the word in a column read as text.
    func tablesHolding(_ word: String) throws -> [String] {
        try writer.read { db in
            let tables = try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
            return try tables.filter { table in
                let columns = try Row.fetchAll(db, sql: "PRAGMA table_info(\"\(table)\")").map { $0["name"] as String }
                let any = columns.map { "instr(CAST(\"\($0)\" AS TEXT), ?) > 0" }.joined(separator: " OR ")
                guard !any.isEmpty else { return false }
                let found =
                    try Int.fetchOne(
                        db, sql: "SELECT count(*) FROM \"\(table)\" WHERE \(any)",
                        arguments: StatementArguments(columns.map { _ in word })) ?? 0
                return found > 0
            }
        }
    }
}
