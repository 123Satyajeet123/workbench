import Foundation
import GRDB

/// What the linked SQLite is, from its own library: the version, the compile options that matter to an erase, and whether
/// the FTS5 option `secure-delete` is there.
enum SqliteInfo {
    static func print(into findings: Findings) throws {
        let queue = try DatabaseQueue()
        try queue.write { db in
            let version = try String.fetchOne(db, sql: "SELECT sqlite_version()") ?? "unknown"
            let options = try String.fetchAll(db, sql: "PRAGMA compile_options")
            let keys = ["SECURE_DELETE", "FTS5", "DBSTAT", "THREADSAFE", "DEFAULT_WAL"]
            let relevant = options.filter { option in keys.contains { option.contains($0) } }
            Swift.print("sqlite_version() = \(version); relevant compile options: \(relevant)")
            Swift.print("PRAGMA secure_delete default = \(try Int.fetchOne(db, sql: "PRAGMA secure_delete") ?? -1)")
            try db.execute(sql: "CREATE VIRTUAL TABLE probe USING fts5(words)")
            let accepted = (try? db.execute(sql: "INSERT INTO probe(probe, rank) VALUES('secure-delete', 1)")) != nil
            Swift.print("fts5 option 'secure-delete' accepted by this library: \(accepted)")
        }
    }
}
