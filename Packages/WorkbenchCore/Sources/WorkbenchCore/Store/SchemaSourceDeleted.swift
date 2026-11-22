import Foundation

extension Schema {
    /// An item whose source message was deleted keeps its row and its marks, and loses its words: `quote` is empty
    /// and `source_deleted` is 1, never one without the other. `item` is rebuilt by the 12-step procedure because
    /// the old check forbade an empty quote.
    static let sourceDeleted = [
        "DROP VIEW item_mark",
        """
        CREATE TABLE item_rebuilt(
            id INTEGER PRIMARY KEY AUTOINCREMENT, task TEXT NOT NULL CHECK(task <> ''),
            run_id INTEGER REFERENCES run(id), day TEXT NOT NULL, scope TEXT NOT NULL, source TEXT NOT NULL,
            cite_first INTEGER NOT NULL, cite_last INTEGER NOT NULL, start_at TEXT NOT NULL, end_at TEXT NOT NULL,
            fields TEXT NOT NULL CHECK(json_valid(fields) AND json_type(fields) = 'object'),
            quote TEXT NOT NULL, created_at TEXT NOT NULL,
            asked_with REAL CHECK(asked_with IS NULL OR (asked_with > 0 AND asked_with <= 1)),
            source_deleted INTEGER NOT NULL DEFAULT 0 CHECK(source_deleted IN (0,1)),
            CHECK(end_at >= start_at), CHECK(cite_last >= cite_first),
            CHECK((source = 'typed') = (run_id IS NULL)),
            CHECK((quote = '') = (source_deleted = 1)))
        """,
        """
        INSERT INTO item_rebuilt(id, task, run_id, day, scope, source, cite_first, cite_last, start_at, end_at, fields,
            quote, created_at, asked_with)
        SELECT id, task, run_id, day, scope, source, cite_first, cite_last, start_at, end_at, fields, quote,
            created_at, asked_with FROM item
        """,
        "DROP TABLE item",
        "ALTER TABLE item_rebuilt RENAME TO item",
        "CREATE INDEX item_day ON item(task, day, scope)",
        "CREATE INDEX item_run ON item(run_id)",
        """
        CREATE VIEW item_mark AS SELECT item.*, COALESCE(
            (SELECT state FROM mark WHERE mark.item_id = item.id ORDER BY mark.id DESC LIMIT 1), 'proposed') AS state
        FROM item
        """,
    ]
}
