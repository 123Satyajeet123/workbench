import Foundation

extension Schema {
    /// The journal of a reading: what it did, in order, one row for each event (`RunEvent`). A reading is named by its
    /// first model call, `run_id`, so deleting that run deletes the journal. `seq` counts from 1 and a row goes at the
    /// end only; nothing follows `finished`; a row never changes; a row goes only with its run. A row holds counts, the
    /// ids of runs and closed names, and never the text of a line, a fact or a reply, so an erase of a line leaves every
    /// row as it is: a line a reading read is reached through `run_input` under the same run. `tag` holds one of: the
    /// hash of the prompt (`started`), a drop rule (`dropped`), a cap (`cap_hit`), a failure kind (`failed`); a
    /// check allows only letters, digits and `_`, up to 64 of them. `by_rule` counts the drops of a part for each rule,
    /// and `cost` is the cost of the model calls of the reading: both are JSON of numbers. A reading made before this
    /// step has no rows.
    static let runEvent = [
        """
        CREATE TABLE run_event(
            run_id INTEGER NOT NULL REFERENCES run(id) ON DELETE CASCADE,
            seq INTEGER NOT NULL CHECK(seq >= 1),
            at TEXT NOT NULL,
            kind TEXT NOT NULL CHECK(kind IN ('started','part_read','proposed','kept','dropped','cap_hit','filed',
                'asked','failed','cancelled','finished')),
            lines INTEGER CHECK(lines IS NULL OR lines >= 0),
            parts INTEGER CHECK(parts IS NULL OR parts >= 1),
            part INTEGER CHECK(part IS NULL OR part >= 1),
            part_run INTEGER,
            count INTEGER CHECK(count IS NULL OR count >= 0),
            tag TEXT CHECK(tag IS NULL OR (length(tag) BETWEEN 1 AND 64 AND tag NOT GLOB '*[^A-Za-z0-9_]*')),
            by_rule TEXT CHECK(by_rule IS NULL OR (json_valid(by_rule) AND json_type(by_rule) = 'object')),
            cost TEXT CHECK(cost IS NULL OR (json_valid(cost) AND json_type(cost) = 'object')),
            PRIMARY KEY(run_id, seq),
            CHECK(CASE
                WHEN kind = 'started' THEN lines IS NOT NULL AND parts IS NOT NULL AND tag IS NOT NULL
                WHEN kind = 'part_read' THEN part IS NOT NULL AND lines IS NOT NULL
                WHEN kind IN ('proposed','kept','filed','asked') THEN count IS NOT NULL
                WHEN kind = 'dropped' THEN by_rule IS NOT NULL
                WHEN kind = 'cap_hit' THEN count IS NOT NULL AND tag IS NOT NULL
                WHEN kind = 'failed' THEN tag IS NOT NULL
                WHEN kind = 'finished' THEN cost IS NOT NULL
                ELSE 1 END)
        ) STRICT, WITHOUT ROWID
        """,
        """
        CREATE TRIGGER run_event_goes_at_the_end BEFORE INSERT ON run_event
        BEGIN SELECT CASE
            WHEN NEW.seq <> (SELECT COALESCE(MAX(seq), 0) + 1 FROM run_event WHERE run_id = NEW.run_id)
                THEN RAISE(ABORT, 'a journal event goes at the end of its journal')
            WHEN EXISTS (SELECT 1 FROM run_event WHERE run_id = NEW.run_id AND kind = 'finished')
                THEN RAISE(ABORT, 'nothing follows finished')
        END; END
        """,
        """
        CREATE TRIGGER run_event_never_changes BEFORE UPDATE ON run_event
        BEGIN SELECT RAISE(ABORT, 'a journal event never changes'); END
        """,
        """
        CREATE TRIGGER run_event_goes_with_its_run BEFORE DELETE ON run_event
        WHEN EXISTS (SELECT 1 FROM run WHERE id = OLD.run_id)
        BEGIN SELECT RAISE(ABORT, 'a journal event goes only with its run'); END
        """,
    ]
}
