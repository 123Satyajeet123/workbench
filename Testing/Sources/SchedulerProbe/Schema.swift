import GRDB

enum ProbeSchema {
    static func create(in db: Database) throws {
        try db.execute(
            sql: """
                CREATE TABLE lines(
                    id INTEGER PRIMARY KEY, machine INTEGER NOT NULL, source INTEGER NOT NULL,
                    arrived_at INTEGER NOT NULL, tombstone INTEGER NOT NULL DEFAULT 0);
                CREATE TABLE consent(source INTEGER PRIMARY KEY, granted INTEGER NOT NULL);
                CREATE TABLE runs(
                    id INTEGER PRIMARY KEY, machine INTEGER NOT NULL, mode TEXT NOT NULL, cause TEXT NOT NULL,
                    due_at INTEGER NOT NULL, state TEXT NOT NULL, due_key TEXT,
                    started_at INTEGER, finish_at INTEGER);
                CREATE TABLE run_input(run_id INTEGER NOT NULL, line_id INTEGER NOT NULL, PRIMARY KEY(run_id, line_id));
                CREATE TABLE facts(
                    id INTEGER PRIMARY KEY, run_id INTEGER NOT NULL, line_id INTEGER NOT NULL, UNIQUE(run_id, line_id));
                CREATE INDEX runs_state ON runs(state, due_at);
                """)
    }

    /// Arm C only: at most one planned row per (machine, mode).
    static func addPlannedUniqueIndex(in db: Database) throws {
        try db.execute(sql: "CREATE UNIQUE INDEX one_planned ON runs(machine, mode) WHERE state = 'planned'")
    }

    /// Arm F only: a planned row is deduplicated by the hash of its frozen window.
    static func addDueKeyIndex(in db: Database) throws {
        try db.execute(sql: "CREATE UNIQUE INDEX one_due_key ON runs(due_key) WHERE state = 'planned'")
    }
}
