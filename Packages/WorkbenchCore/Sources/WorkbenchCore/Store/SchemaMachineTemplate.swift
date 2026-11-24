import Foundation

extension Schema {
    /// A machine made from a source and a job has no template, so `machine.template` may hold NULL. SQLite cannot drop
    /// a NOT NULL, so `machine` is rebuilt: its rows go to a copy, the table is made again with the column open, and
    /// every row comes back with every value as it was. The table is dropped and made again under its own name and is
    /// never renamed, so the view `machine_now` and the triggers that name it stay as they are. The other columns,
    /// their checks and the foreign keys to the table are the ones it had.
    static let machineWithoutTemplate = [
        "CREATE TABLE machine_copy AS SELECT id, task, template, created_at, page_id FROM machine",
        "DROP TABLE machine",
        """
        CREATE TABLE machine(
            id INTEGER PRIMARY KEY, task TEXT NOT NULL UNIQUE CHECK(task <> ''), template TEXT,
            created_at TEXT NOT NULL, page_id TEXT REFERENCES work_object(id))
        """,
        """
        INSERT INTO machine(id, task, template, created_at, page_id)
        SELECT id, task, template, created_at, page_id FROM machine_copy
        """,
        "DROP TABLE machine_copy",
    ]
}
