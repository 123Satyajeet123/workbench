import Foundation

extension Schema {
    /// The fact lifecycle as events (research 59 §1 Lifecycle row). `item_event` is rebuilt for the new kinds: `open`
    /// (made when an item is inserted), `restate`, `due_changed` (`due` holds the new date), `supersede` (`successor` is
    /// the item that replaces it), `close_proposed`, `close`, `reopen`, `withdraw` and `flag`, beside the hide kinds.
    /// A model event carries its run, line and quote; a person's carries its actor. A model writes no close, reopen,
    /// withdraw or hide, and only a model proposes a close. A row never changes; the one allowed change is the erase
    /// of a model quote to empty. Status is the latest of supersede, close, reopen and withdraw by valid time, then
    /// record time, then id. A close proposal is pending until a later event on the item. The rebuild keeps every id
    /// and every `line_id`. A model close becomes a proposal, so `status_change` logs each item whose status the new
    /// order changes, with its reason.
    static let factLifecycle = [
        """
        CREATE TABLE status_change(
            item_id INTEGER PRIMARY KEY REFERENCES item(id) ON DELETE CASCADE,
            was TEXT NOT NULL CHECK(was IN ('open','closed')), now TEXT NOT NULL CHECK(now IN ('open','closed')),
            reason TEXT NOT NULL CHECK(reason IN ('model_close_became_a_proposal','valid_time_order')),
            CHECK(was <> now))
        """,
        """
        INSERT INTO status_change(item_id, was, now, reason)
        SELECT item.id, CASE old.kind WHEN 'close' THEN 'closed' ELSE 'open' END,
            CASE latest.kind WHEN 'close' THEN 'closed' ELSE 'open' END,
            CASE old.actor WHEN 'model' THEN 'model_close_became_a_proposal' ELSE 'valid_time_order' END
        FROM item
        JOIN (
            SELECT item_id, kind, actor FROM item_event WHERE id IN (
                SELECT MAX(id) FROM item_event WHERE kind IN ('close','reopen') GROUP BY item_id)
        ) old ON old.item_id = item.id
        LEFT JOIN (
            SELECT item_id, kind FROM (
                SELECT item_id, kind, ROW_NUMBER() OVER (
                    PARTITION BY item_id ORDER BY valid_at DESC, recorded_at DESC, id DESC) AS rank
                FROM item_event WHERE actor = 'person' AND kind IN ('close','reopen')) WHERE rank = 1
        ) latest ON latest.item_id = item.id
        WHERE (old.kind = 'close') <> (latest.kind IS 'close')
        """,
        "DROP VIEW item_status",
        "DROP VIEW item_hiding",
        """
        CREATE TABLE item_event_rebuilt(
            id INTEGER PRIMARY KEY, item_id INTEGER NOT NULL REFERENCES item(id) ON DELETE CASCADE,
            kind TEXT NOT NULL CHECK(kind IN ('open','restate','due_changed','supersede','close_proposed','close',
                'reopen','withdraw','flag','hide','snooze','unhide')),
            outcome TEXT, line_id INTEGER, quote TEXT, valid_at TEXT NOT NULL, recorded_at TEXT NOT NULL,
            run_id INTEGER REFERENCES run(id), actor TEXT NOT NULL CHECK(actor IN ('model','person')), until TEXT,
            due TEXT, successor INTEGER REFERENCES item(id) ON DELETE CASCADE,
            CHECK((kind IN ('close','close_proposed')) = (outcome IS NOT NULL AND outcome <> '')),
            CHECK((kind = 'snooze') = (until IS NOT NULL)),
            CHECK((kind = 'due_changed') = (due IS NOT NULL AND due <> '')),
            CHECK((kind = 'supersede') = (successor IS NOT NULL)),
            CHECK(actor = 'person' OR kind IN ('open','restate','due_changed','supersede','close_proposed','flag')),
            CHECK(kind <> 'close_proposed' OR actor = 'model'),
            CHECK((actor = 'model') = (run_id IS NOT NULL AND line_id IS NOT NULL AND quote IS NOT NULL)))
        """,
        """
        INSERT INTO item_event_rebuilt(id, item_id, kind, outcome, line_id, quote, valid_at, recorded_at, run_id, actor,
            until)
        SELECT id, item_id,
            CASE WHEN actor = 'model' AND kind = 'close' THEN 'close_proposed'
                WHEN actor = 'model' AND kind = 'reopen' THEN 'flag' ELSE kind END,
            CASE WHEN actor = 'model' AND kind = 'reopen' THEN NULL ELSE outcome END,
            line_id, quote, valid_at, recorded_at, run_id, actor, until
        FROM item_event
        """,
        "DROP TABLE item_event",
        "ALTER TABLE item_event_rebuilt RENAME TO item_event",
        "CREATE INDEX item_event_item ON item_event(item_id, id)",
        """
        INSERT INTO item_event(item_id, kind, line_id, quote, valid_at, recorded_at, run_id, actor)
        SELECT id, 'open', CASE WHEN run_id IS NULL THEN NULL ELSE cite_first END,
            CASE WHEN run_id IS NULL THEN NULL ELSE quote END, start_at, created_at, run_id,
            CASE WHEN run_id IS NULL THEN 'person' ELSE 'model' END
        FROM item ORDER BY id
        """,
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
            AND NEW.successor IS OLD.successor)
        BEGIN SELECT RAISE(ABORT, 'an event never changes except the erase of a model quote'); END
        """,
        """
        CREATE TRIGGER status_change_never_changes BEFORE UPDATE ON status_change
        BEGIN SELECT RAISE(ABORT, 'a status change never changes'); END
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
    ]
}
