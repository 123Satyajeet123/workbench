import Foundation
import GRDB
import Kernel
import PageSnapshot

@testable import WorkbenchCore

/// A store made before the step: the machine table holds a template that cannot be empty. The step rebuilds the
/// table, every row of every table is equal after it, and then an empty template is accepted.
@MainActor
enum OldShape {
    static func run() throws {
        heading("8. A store from before the schema step")
        let folder = FileManager.default.temporaryDirectory.appending(path: "blank-machine-old-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        do { try fill(try Store(directory: folder)) }
        let old = try StoreDatabase.open(at: folder.appending(path: "workbench.sqlite"), busyTimeout: 10)
        try old.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA foreign_keys = OFF")
            try db.inTransaction {
                for statement in oldShape { try db.execute(sql: statement) }
                try db.execute(sql: "PRAGMA user_version = \(Schema.version - 1)")
                return .commit
            }
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let before = try tables(old)
        let oldDefinition = try definition(old)
        check(
            "the machine table is in its old shape: the template cannot be empty",
            oldDefinition.contains("template TEXT NOT NULL"))
        let refusedBefore = (try? old.write { try insertMachine($0, template: nil) }) == nil
        check("the old shape refuses a machine with no template", refusedBefore)
        let migrated = try Store(directory: folder)
        let after = try tables(migrated.writer)
        let changed = before.keys.filter { $0 != "state" && after[$0] != before[$0] }.sorted()
        print(
            "  tables: \(before.count); machine rows: \(before["machine"]?.count ?? 0); changed by the step: \(changed)"
        )
        check("the stored version is the newest", try Schema.storedVersion(migrated.writer) == Schema.version)
        check("every row of every table is equal after the step", changed.isEmpty)
        check(
            "the machine table now lets the template be empty",
            try definition(migrated.writer).contains("template TEXT,"))
        check(
            "a machine with no template is accepted",
            (try? migrated.writer.write { try insertMachine($0, template: nil) }) != nil)
        check("a machine of a template is kept as it was", try migrated.queries.machines().count == 3)
        try migrated.writer.read { try $0.checkForeignKeys() }
        check("every foreign key holds after the step", true)
    }

    private static func fill(_ store: Store) throws {
        let pip = try store.createMachine(from: .team, template: MachineTemplate.team.id, name: "Pip Example")
        _ = try saveSyntheticFacts(
            in: store, of: pip, owner: try PersonID("old-shape-owner"), scope: "old-shape",
            sources: ["Asha: Example Cafe wants the menu"], quotes: ["Example Cafe wants the menu"],
            fields: [
                [
                    "person": "Asha", "project": "Menu", "kind": "plan", "text": "Menu for Example Cafe",
                    "stance": "said", "asks": "team",
                ]
            ])
        _ = try store.createMachine(from: .dealIntake, template: MachineTemplate.dealIntake.id, name: "Intake Example")
        let third = try store.createMachine(from: .timeline, template: MachineTemplate.timeline.id, name: "Day Example")
        try store.rename(third, to: "Day renamed Example")
    }

    private static func insertMachine(_ db: Database, template: String?) throws {
        try db.execute(
            sql:
                "INSERT INTO machine(task, template, created_at) VALUES ('machine-aaaaaaaa', ?, '2026-11-25T00:00:00Z')",
            arguments: [template])
    }

    private static func definition(_ writer: DatabasePool) throws -> String {
        try writer.read { try String.fetchOne($0, sql: "SELECT sql FROM sqlite_master WHERE name = 'machine'") ?? "" }
    }

    /// Every table with its rows as text, so two states compare by what they hold.
    private static func tables(_ writer: DatabasePool) throws -> [String: [String]] {
        try writer.read { db in
            let names = try String.fetchAll(
                db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")
            return try Dictionary(
                uniqueKeysWithValues: names.map { name in
                    (name, try Row.fetchAll(db, sql: "SELECT * FROM \"\(name)\"").map { "\($0)" }.sorted())
                })
        }
    }

    /// The machine table as it stood before the step, made again under its own name.
    private static let oldShape = [
        "CREATE TABLE machine_copy AS SELECT id, task, template, created_at, page_id FROM machine",
        "DROP TABLE machine",
        """
        CREATE TABLE machine(
            id INTEGER PRIMARY KEY, task TEXT NOT NULL UNIQUE CHECK(task <> ''), template TEXT NOT NULL,
            created_at TEXT NOT NULL, page_id TEXT REFERENCES work_object(id))
        """,
        "INSERT INTO machine(id, task, template, created_at, page_id) SELECT id, task, template, created_at, page_id FROM machine_copy",
        "DROP TABLE machine_copy",
    ]
}
