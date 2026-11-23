import Foundation

extension Schema {
    /// The person's marks as lifecycle events (research 49, P1 §1.7). `item_event` is rebuilt with three columns and one
    /// kind. `surface` is where the person acted (`MarkSurface`); a model event has none, and a new person event of a
    /// mark kind must have one. `hand_off` gives the fact to another person in `handed_to`; a hand off with no person
    /// takes the earlier one back. `batch_id` ties the closes and reopens of one "mark everything older as handled" to
    /// its row in `handled_batch`, which holds the one bulk event: when, where, and the cutoff. Nothing is deleted; a
    /// reopen takes the batch back. The rebuild keeps every id.
    static let morningList = [
        """
        CREATE TABLE handled_batch(
            id INTEGER PRIMARY KEY, recorded_at TEXT NOT NULL, actor TEXT NOT NULL CHECK(actor = 'person'),
            surface TEXT NOT NULL CHECK(surface IN ('today','review','notification','menu_bar','island','machine_page','deals')),
            older_than_days INTEGER NOT NULL CHECK(older_than_days > 0), cutoff_day TEXT NOT NULL)
        """,
        "DROP TRIGGER item_opens",
        "DROP TRIGGER item_event_never_changes",
        "DROP VIEW item_status",
        "DROP VIEW item_hiding",
        "DROP VIEW item_due",
        "DROP VIEW item_proposal",
        """
        CREATE TABLE item_event_rebuilt(
            id INTEGER PRIMARY KEY, item_id INTEGER NOT NULL REFERENCES item(id) ON DELETE CASCADE,
            kind TEXT NOT NULL CHECK(kind IN ('open','restate','due_changed','supersede','close_proposed','close',
                'reopen','withdraw','flag','hide','snooze','unhide','hand_off')),
            outcome TEXT, line_id INTEGER, quote TEXT, valid_at TEXT NOT NULL, recorded_at TEXT NOT NULL,
            run_id INTEGER REFERENCES run(id), actor TEXT NOT NULL CHECK(actor IN ('model','person')), until TEXT,
            due TEXT, successor INTEGER REFERENCES item(id) ON DELETE CASCADE,
            surface TEXT CHECK(surface IN ('today','review','notification','menu_bar','island','machine_page','deals')),
            handed_to TEXT CHECK(handed_to <> ''), batch_id INTEGER REFERENCES handled_batch(id),
            CHECK((kind IN ('close','close_proposed')) = (outcome IS NOT NULL AND outcome <> '')),
            CHECK((kind = 'snooze') = (until IS NOT NULL)),
            CHECK((kind = 'due_changed') = (due IS NOT NULL AND due <> '')),
            CHECK((kind = 'supersede') = (successor IS NOT NULL)),
            CHECK(actor = 'person' OR kind IN ('open','restate','due_changed','supersede','close_proposed','flag')),
            CHECK(kind <> 'close_proposed' OR actor = 'model'),
            CHECK(actor = 'person' OR surface IS NULL),
            CHECK(kind = 'hand_off' OR handed_to IS NULL),
            CHECK(batch_id IS NULL OR kind IN ('close','reopen')),
            CHECK((actor = 'model') = (run_id IS NOT NULL AND line_id IS NOT NULL AND quote IS NOT NULL)))
        """,
        """
        INSERT INTO item_event_rebuilt(id, item_id, kind, outcome, line_id, quote, valid_at, recorded_at, run_id, actor,
            until, due, successor)
        SELECT id, item_id, kind, outcome, line_id, quote, valid_at, recorded_at, run_id, actor, until, due, successor
        FROM item_event
        """,
        "DROP TABLE item_event",
        "ALTER TABLE item_event_rebuilt RENAME TO item_event",
        "CREATE INDEX item_event_item ON item_event(item_id, id)",
        """
        CREATE TRIGGER item_opens AFTER INSERT ON item
        BEGIN
            INSERT INTO item_event(item_id, kind, line_id, quote, valid_at, recorded_at, run_id, actor)
            VALUES (NEW.id, 'open', CASE WHEN NEW.run_id IS NULL THEN NULL ELSE NEW.cite_first END,
                CASE WHEN NEW.run_id IS NULL THEN NULL ELSE NEW.quote END, NEW.start_at, NEW.created_at, NEW.run_id,
                CASE WHEN NEW.run_id IS NULL THEN 'person' ELSE 'model' END);
        END
        """,
        """
        CREATE TRIGGER item_event_never_changes BEFORE UPDATE ON item_event
        WHEN NOT (NEW.quote = '' AND OLD.actor = 'model' AND NEW.id IS OLD.id AND NEW.item_id IS OLD.item_id
            AND NEW.kind IS OLD.kind AND NEW.outcome IS OLD.outcome AND NEW.line_id IS OLD.line_id
            AND NEW.valid_at IS OLD.valid_at AND NEW.recorded_at IS OLD.recorded_at AND NEW.run_id IS OLD.run_id
            AND NEW.actor IS OLD.actor AND NEW.until IS OLD.until AND NEW.due IS OLD.due
            AND NEW.successor IS OLD.successor AND NEW.surface IS OLD.surface AND NEW.handed_to IS OLD.handed_to
            AND NEW.batch_id IS OLD.batch_id)
        BEGIN SELECT RAISE(ABORT, 'an event never changes except the erase of a model quote'); END
        """,
        """
        CREATE TRIGGER item_event_has_surface BEFORE INSERT ON item_event
        WHEN NEW.actor = 'person' AND NEW.surface IS NULL
            AND NEW.kind IN ('close','reopen','withdraw','hide','snooze','unhide','hand_off')
        BEGIN SELECT RAISE(ABORT, 'a mark of a person records its surface'); END
        """,
        """
        CREATE VIEW item_status AS SELECT item_id, kind AS status_kind,
            COALESCE(outcome, CASE kind WHEN 'supersede' THEN 'superseded' WHEN 'withdraw' THEN 'withdrawn' END)
                AS status_outcome,
            quote AS status_quote, valid_at AS status_at, actor AS status_actor
        FROM (SELECT *, ROW_NUMBER() OVER (
                PARTITION BY item_id ORDER BY valid_at DESC, recorded_at DESC, id DESC) AS rank
            FROM item_event WHERE kind IN ('supersede','close','reopen','withdraw')) WHERE rank = 1
        """,
        """
        CREATE VIEW item_hiding AS SELECT item_id, kind AS hiding_kind, until AS hiding_until
        FROM (SELECT *, ROW_NUMBER() OVER (
                PARTITION BY item_id ORDER BY valid_at DESC, recorded_at DESC, id DESC) AS rank
            FROM item_event WHERE kind IN ('hide','snooze','unhide')) WHERE rank = 1
        """,
        """
        CREATE VIEW item_due AS SELECT item_id, due AS due_value
        FROM (SELECT *, ROW_NUMBER() OVER (
                PARTITION BY item_id ORDER BY valid_at DESC, recorded_at DESC, id DESC) AS rank
            FROM item_event WHERE kind = 'due_changed') WHERE rank = 1
        """,
        """
        CREATE VIEW item_proposal AS SELECT item_id, outcome AS proposal_outcome, quote AS proposal_quote,
            valid_at AS proposal_at
        FROM (SELECT *, ROW_NUMBER() OVER (
                PARTITION BY item_id ORDER BY valid_at DESC, recorded_at DESC, id DESC) AS rank
            FROM item_event WHERE kind = 'close_proposed') proposed
        WHERE rank = 1 AND NOT EXISTS (
            SELECT 1 FROM item_event acted WHERE acted.item_id = proposed.item_id
                AND acted.kind IN ('supersede','close','reopen','withdraw')
                AND (acted.recorded_at, acted.id) > (proposed.recorded_at, proposed.id))
        """,
        """
        CREATE VIEW item_handoff AS SELECT item_id, handed_to AS handoff_to
        FROM (SELECT *, ROW_NUMBER() OVER (
                PARTITION BY item_id ORDER BY valid_at DESC, recorded_at DESC, id DESC) AS rank
            FROM item_event WHERE kind = 'hand_off') WHERE rank = 1 AND handed_to IS NOT NULL
        """,
    ]
}
