import Foundation

extension Schema {
    /// The lines one model run read (research 59 §1 Window row). `ordinal` is the number in front of the line in the
    /// run's input, so an item's cite number resolves through `(run_id, ordinal)` to the line that run saw, even when
    /// the source has changed since. A row holds no text. It is written once; `run_id` and `ordinal` never change. The
    /// one change allowed is the revoke of its message: `line_id` moves to the tombstone of the same container, and the
    /// text line goes. Deleting a line, or a run, deletes its rows.
    static let runWindow = [
        """
        CREATE TABLE run_window(
            run_id INTEGER NOT NULL REFERENCES run(id) ON DELETE CASCADE,
            ordinal INTEGER NOT NULL,
            line_id BLOB NOT NULL CHECK(length(line_id) = 32) REFERENCES evidence(line_id) ON DELETE CASCADE,
            PRIMARY KEY(run_id, ordinal)
        ) STRICT, WITHOUT ROWID
        """,
        "CREATE INDEX run_window_line ON run_window(line_id)",
        """
        CREATE TRIGGER run_window_written_once BEFORE INSERT ON run_window
        BEGIN SELECT CASE
            WHEN EXISTS (SELECT 1 FROM run_window WHERE run_id = NEW.run_id AND ordinal = NEW.ordinal
                AND line_id IS NOT NEW.line_id) THEN RAISE(ABORT, 'a run window never changes')
            WHEN EXISTS (SELECT 1 FROM run_window WHERE run_id = NEW.run_id AND ordinal = NEW.ordinal)
                THEN RAISE(IGNORE)
        END; END
        """,
        """
        CREATE TRIGGER run_window_never_changes BEFORE UPDATE OF run_id, ordinal ON run_window
        BEGIN SELECT RAISE(ABORT, 'a run window never changes'); END
        """,
        """
        CREATE TRIGGER run_window_only_a_revoke_moves_a_line BEFORE UPDATE OF line_id ON run_window
        WHEN NOT EXISTS (
            SELECT 1 FROM evidence tombstone WHERE tombstone.line_id = NEW.line_id AND tombstone.tombstone = 1
                AND tombstone.container = (SELECT container FROM evidence WHERE line_id = OLD.line_id))
        BEGIN SELECT RAISE(ABORT, 'only a revoke moves a run window line to its tombstone'); END
        """,
    ]
}
