import Foundation

extension Schema {
    /// The founder's actions on an item as events: hide it, snooze it until a time, or bring it back. They sit beside
    /// the model's and the founder's closes in `item_event`, rebuilt for the new kinds and `until`; a close never
    /// hides, and a hide never closes, so each has its own latest-event view. A model only ever closes.
    static let itemActions = [
        "DROP VIEW item_status",
        """
        CREATE TABLE item_event_rebuilt(
            id INTEGER PRIMARY KEY, item_id INTEGER NOT NULL REFERENCES item(id) ON DELETE CASCADE,
            kind TEXT NOT NULL CHECK(kind IN ('close','reopen','hide','snooze','unhide')), outcome TEXT, line_id INTEGER,
            quote TEXT, valid_at TEXT NOT NULL, recorded_at TEXT NOT NULL, run_id INTEGER REFERENCES run(id),
            actor TEXT NOT NULL CHECK(actor IN ('model','person')), until TEXT,
            CHECK((kind = 'close') = (outcome IS NOT NULL AND outcome <> '')),
            CHECK((kind = 'snooze') = (until IS NOT NULL)),
            CHECK(kind IN ('close','reopen') OR actor = 'person'),
            CHECK((actor = 'model') = (run_id IS NOT NULL AND line_id IS NOT NULL AND quote IS NOT NULL)))
        """,
        """
        INSERT INTO item_event_rebuilt(id, item_id, kind, outcome, line_id, quote, valid_at, recorded_at, run_id, actor)
        SELECT id, item_id, kind, outcome, line_id, quote, valid_at, recorded_at, run_id, actor FROM item_event
        """,
        "DROP TABLE item_event",
        "ALTER TABLE item_event_rebuilt RENAME TO item_event",
        "CREATE INDEX item_event_item ON item_event(item_id, id)",
        """
        CREATE VIEW item_status AS SELECT item_id, kind AS status_kind, outcome AS status_outcome,
            quote AS status_quote, valid_at AS status_at, actor AS status_actor
        FROM item_event WHERE id IN (
            SELECT MAX(id) FROM item_event WHERE kind IN ('close','reopen') GROUP BY item_id)
        """,
        """
        CREATE VIEW item_hiding AS SELECT item_id, kind AS hiding_kind, until AS hiding_until
        FROM item_event WHERE id IN (
            SELECT MAX(id) FROM item_event WHERE kind IN ('hide','snooze','unhide') GROUP BY item_id)
        """,
    ]
}
