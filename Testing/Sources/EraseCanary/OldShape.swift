import Foundation
import GRDB

@testable import WorkbenchCore

/// A store made before the last schema step: opening it runs the step, every row stays as it was, and an erase of a line
/// that was indexed before the step leaves no byte of it.
enum OldShape {
    static func run(in folder: URL, findings: Findings) async throws {
        print("\n== a store from before the step that turns on secure-delete in the search indexes")
        let scene = try Scene(in: folder, words: Words())
        try await scene.build()
        let before = try rows(of: scene.store)
        try await scene.store.writer.writeWithoutTransaction { db in
            for index in ["evidence_fts", "item_fts"] {
                try db.execute(sql: "INSERT INTO \(index)(\(index), rank) VALUES('secure-delete', 0)")
            }
            try db.execute(sql: "PRAGMA user_version = \(Schema.steps.count - 1)")
        }
        try scene.reopen()
        let after = try rows(of: scene.store)
        findings.expect(before == after, "the rows of every table are equal after the step (\(before.count) tables)")
        let option = try scene.store.count(
            "SELECT count(*) FROM evidence_fts_config WHERE k = 'secure-delete' AND v = 1")
        findings.expect(option == 1, "the step turned the option on")
        try await Trigger.revoke.fire(scene)
        for hit in ByteScan.hits(of: scene.words.canary, under: scene.directory) where !hit.file.hasPrefix("agent-work")
        {
            findings.leak("old shape: canary in \(hit.file) at byte \(hit.offset), \(hit.place)")
        }
        try scene.store.writer.close()
    }

    /// Every row of every table but the two option tables, as text, so two stores compare.
    private static func rows(of store: Store) throws -> [String: [String]] {
        try store.writer.read { db in
            let tables = try String.fetchAll(
                db,
                sql: """
                    SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
                        AND name NOT IN ('evidence_fts_config', 'item_fts_config') ORDER BY name
                    """)
            return try Dictionary(
                uniqueKeysWithValues: tables.map { table in
                    (table, try Row.fetchAll(db, sql: "SELECT * FROM \"\(table)\"").map(\.description).sorted())
                })
        }
    }
}
