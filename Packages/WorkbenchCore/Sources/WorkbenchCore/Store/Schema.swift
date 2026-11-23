import Foundation
import GRDB

/// The schema of `workbench.sqlite` as an append-only list of steps. `user_version` counts the steps a store has run;
/// opening a store runs the steps it lacks, in one transaction. A shipped step never changes (`SchemaTests` pins each
/// one's digest), so a step is literal text: a new need is a new step after the last. A store from a newer Workbench
/// is refused. The first step is the whole schema as of 2026-11-19; the steps that led to it, written while there was
/// no data worth keeping, were folded into it.
enum Schema {
    static var version: Int32 { Int32(steps.count) }

    /// Reads the version and runs the missing steps in one write transaction, so a second process that opens the same
    /// file waits, then finds the steps done. Foreign keys are off while the steps run, because a step may rebuild a
    /// table that others reference (a drop with foreign keys on would cascade into them). They are checked before the
    /// transaction commits and switched on again after it.
    static func open(_ writer: some DatabaseWriter, ownerZone: TimeZone = .current) throws {
        try writer.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA foreign_keys = OFF")
            defer { try? db.execute(sql: "PRAGMA foreign_keys = ON") }
            try db.inTransaction(.immediate) {
                let found = try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
                guard found <= steps.count else { throw SchemaError.newerVersion }
                guard found < steps.count else { return .commit }
                for statement in steps[found...].joined() { try db.execute(sql: statement) }
                if let index = steps.firstIndex(of: timers), found <= index {
                    try moveLegacyDueDays(db, zone: ownerZone)
                }
                if let index = steps.firstIndex(of: filing), found <= index { try WorkObjectsMove.run(db) }
                try db.checkForeignKeys()
                try db.execute(sql: "PRAGMA user_version = \(version)")
                return .commit
            }
        }
    }

    static var stepDigests: [String] { steps.map { Digest.sha256($0.joined(separator: ";\n")) } }

    static let steps = [
        baseline, itemEvents, runText, summaries, itemActions, mail, typedItems, quoteMarks, newsArticles, evidence,
        runWindow, sourceDeleted, groundedFacts, factLifecycle, timers, evidenceForwarded,
        morningList, notes, pendingRevokes, filing, itemSearch, runFailures, calls, callGuests, machinePage,
    ]

    /// Items that open and close (research 32): a later line closes a commitment or answers a question. An event is
    /// never rewritten; the latest one is the item's state. Valid time is when the closing line was said; record time
    /// is when the app learned it.
    private static let itemEvents = [
        """
        CREATE TABLE item_event(
            id INTEGER PRIMARY KEY, item_id INTEGER NOT NULL REFERENCES item(id) ON DELETE CASCADE,
            kind TEXT NOT NULL CHECK(kind IN ('close','reopen')), outcome TEXT, line_id INTEGER, quote TEXT,
            valid_at TEXT NOT NULL, recorded_at TEXT NOT NULL, run_id INTEGER REFERENCES run(id),
            actor TEXT NOT NULL CHECK(actor IN ('model','person')),
            CHECK((kind = 'close') = (outcome IS NOT NULL AND outcome <> '')),
            CHECK((actor = 'model') = (run_id IS NOT NULL AND line_id IS NOT NULL AND quote IS NOT NULL)))
        """,
        "CREATE INDEX item_event_item ON item_event(item_id, id)",
        """
        CREATE VIEW item_status AS SELECT item_id, kind AS status_kind, outcome AS status_outcome,
            quote AS status_quote, valid_at AS status_at, actor AS status_actor
        FROM item_event WHERE id IN (SELECT MAX(id) FROM item_event GROUP BY item_id)
        """,
    ]

    /// Replayable runs: what each run was asked and answered, with the consent kinds its input holds. Also the
    /// indexes that foreign-key and join columns lacked, and `item` rebuilt with AUTOINCREMENT by the 12-step
    /// procedure of the SQLite ALTER TABLE document, "Making Other Kinds Of Table Schema Changes".
    private static let runText = [
        """
        CREATE TABLE run_text(
            run_id INTEGER PRIMARY KEY REFERENCES run(id) ON DELETE CASCADE, input TEXT NOT NULL, reply TEXT,
            kinds TEXT NOT NULL CHECK(json_valid(kinds) AND json_type(kinds) = 'array'))
        """,
        "CREATE INDEX machine_change_machine ON machine_change(machine_id, id)",
        "CREATE INDEX proposal_decision_proposal ON proposal_decision(proposal_id, id)",
        "CREATE INDEX member_team ON member(team_id)",
        "CREATE INDEX member_handle_member ON member_handle(member_id)",
        "CREATE INDEX proposal_run ON proposal(run_id)",
        "DROP VIEW item_mark",
        """
        CREATE TABLE item_rebuilt(
            id INTEGER PRIMARY KEY AUTOINCREMENT, task TEXT NOT NULL CHECK(task <> ''),
            run_id INTEGER NOT NULL REFERENCES run(id), day TEXT NOT NULL, scope TEXT NOT NULL, source TEXT NOT NULL,
            cite_first INTEGER NOT NULL, cite_last INTEGER NOT NULL, start_at TEXT NOT NULL, end_at TEXT NOT NULL,
            fields TEXT NOT NULL CHECK(json_valid(fields) AND json_type(fields) = 'object'),
            quote TEXT NOT NULL CHECK(quote <> ''), created_at TEXT NOT NULL,
            asked_with REAL CHECK(asked_with IS NULL OR (asked_with > 0 AND asked_with <= 1)),
            CHECK(end_at >= start_at), CHECK(cite_last >= cite_first))
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

    /// Cited summaries of a day's items per scope (a person or a project), derived data kept so a page does not ask the
    /// model again. The fingerprint is a hash of the scope's input; a changed scope no longer matches it. `kinds` are
    /// the consent kinds the summary was built from, for a privacy delete.
    private static let summaries = [
        """
        CREATE TABLE summary(
            day TEXT NOT NULL, task TEXT NOT NULL CHECK(task <> ''), field TEXT NOT NULL CHECK(field <> ''),
            scope TEXT NOT NULL CHECK(scope <> ''), fingerprint TEXT NOT NULL,
            kinds TEXT NOT NULL CHECK(json_valid(kinds) AND json_type(kinds) = 'array'),
            body TEXT NOT NULL CHECK(json_valid(body) AND json_type(body) = 'object'), saved_at TEXT NOT NULL,
            PRIMARY KEY(day, task, field, scope)) WITHOUT ROWID
        """
    ]

    /// Gmail threads the person opened inside the label they named (research 41). A part is one message of a thread, or
    /// one page of a deck attached to a message (`name` is the file, `page` counts from 1; a message has no name and
    /// page 0). A part is stored once per message id. `mail_open` counts each thread once per day it was opened.
    private static let mail = [
        """
        CREATE TABLE mail_part(
            id INTEGER PRIMARY KEY, thread_id TEXT NOT NULL CHECK(thread_id <> ''),
            message_id TEXT NOT NULL CHECK(message_id <> ''), kind TEXT NOT NULL CHECK(kind IN ('message','deck')),
            name TEXT NOT NULL, page INTEGER NOT NULL CHECK(page >= 0), label TEXT NOT NULL CHECK(label <> ''),
            sender TEXT NOT NULL, subject TEXT NOT NULL, sent_at TEXT NOT NULL, seen_at TEXT NOT NULL,
            text TEXT NOT NULL CHECK(text <> ''), UNIQUE(message_id, name, page),
            CHECK((kind = 'message') = (name = '' AND page = 0)))
        """,
        "CREATE INDEX mail_part_seen ON mail_part(seen_at)",
        """
        CREATE TABLE mail_open(
            thread_id TEXT NOT NULL, day TEXT NOT NULL, label TEXT NOT NULL, PRIMARY KEY(thread_id, day)
        ) WITHOUT ROWID
        """,
    ]

    /// Facts the person typed (the kind `typed`) have no model run: `item.run_id` may be null, and is null exactly for
    /// that kind. `item` is rebuilt by the 12-step procedure, and the old deal actions move: they become `typed`, lose
    /// their run, and the zero-cost runs that stood for them go.
    private static let typedItems = [
        "DROP VIEW item_mark",
        """
        CREATE TABLE item_rebuilt(
            id INTEGER PRIMARY KEY AUTOINCREMENT, task TEXT NOT NULL CHECK(task <> ''),
            run_id INTEGER REFERENCES run(id), day TEXT NOT NULL, scope TEXT NOT NULL, source TEXT NOT NULL,
            cite_first INTEGER NOT NULL, cite_last INTEGER NOT NULL, start_at TEXT NOT NULL, end_at TEXT NOT NULL,
            fields TEXT NOT NULL CHECK(json_valid(fields) AND json_type(fields) = 'object'),
            quote TEXT NOT NULL CHECK(quote <> ''), created_at TEXT NOT NULL,
            asked_with REAL CHECK(asked_with IS NULL OR (asked_with > 0 AND asked_with <= 1)),
            CHECK(end_at >= start_at), CHECK(cite_last >= cite_first),
            CHECK((source = 'typed') = (run_id IS NULL)))
        """,
        """
        INSERT INTO item_rebuilt(id, task, run_id, day, scope, source, cite_first, cite_last, start_at, end_at, fields,
            quote, created_at, asked_with)
        SELECT item.id, item.task, CASE WHEN made_by_you THEN NULL ELSE item.run_id END, item.day, item.scope,
            CASE WHEN made_by_you THEN 'typed' ELSE item.source END, item.cite_first, item.cite_last, item.start_at,
            item.end_at, item.fields, item.quote, item.created_at, item.asked_with
        FROM (SELECT item.*, run.task = 'vc.deal-actions' AND run.model = 'you' AS made_by_you
            FROM item LEFT JOIN run ON run.id = item.run_id) AS item
        """,
        "DROP TABLE item",
        "ALTER TABLE item_rebuilt RENAME TO item",
        "DELETE FROM run WHERE task = 'vc.deal-actions' AND model = 'you'",
        "CREATE INDEX item_day ON item(task, day, scope)",
        "CREATE INDEX item_run ON item(run_id)",
        """
        CREATE VIEW item_mark AS SELECT item.*, COALESCE(
            (SELECT state FROM mark WHERE mark.item_id = item.id ORDER BY mark.id DESC LIMIT 1), 'proposed') AS state
        FROM item
        """,
    ]

    /// The founder's second mark on a claim check: is its quote right. The first, is the verdict right, is the item's
    /// own mark. Like a mark, each one is a new row and the latest stands.
    private static let quoteMarks = [
        """
        CREATE TABLE quote_mark(
            id INTEGER PRIMARY KEY, item_id INTEGER NOT NULL REFERENCES item(id) ON DELETE CASCADE, ts TEXT NOT NULL,
            state TEXT NOT NULL CHECK(state IN ('proposed','confirmed','rejected')))
        """,
        "CREATE INDEX quote_mark_item ON quote_mark(item_id, id)",
    ]

    /// Articles fetched from the news feeds for the portfolio watch, kept 30 days and removed with the kind `web`. An
    /// article is stored once per address; `read_at` is set when its signals were read.
    private static let newsArticles = [
        """
        CREATE TABLE news_article(
            id INTEGER PRIMARY KEY, feed TEXT NOT NULL CHECK(feed <> ''), url TEXT NOT NULL UNIQUE CHECK(url <> ''),
            title TEXT NOT NULL, published_at TEXT NOT NULL, fetched_at TEXT NOT NULL, text TEXT NOT NULL,
            read_at TEXT)
        """,
        "CREATE INDEX news_article_fetched ON news_article(fetched_at)",
    ]

    private static let baseline = [
        "CREATE TABLE state(key TEXT PRIMARY KEY, value TEXT NOT NULL, saved_at TEXT NOT NULL)",
        "CREATE TABLE consent(id INTEGER PRIMARY KEY, ts TEXT NOT NULL, policy TEXT NOT NULL)",
        """
        CREATE TABLE run(
            id INTEGER PRIMARY KEY, task TEXT NOT NULL CHECK(task <> ''), model TEXT NOT NULL, prompt TEXT NOT NULL,
            input_bytes INTEGER NOT NULL, input_sha TEXT NOT NULL, started_at TEXT NOT NULL, ended_at TEXT,
            outcome TEXT NOT NULL CHECK(outcome IN ('running','done','failed')), error TEXT,
            input_tokens INTEGER NOT NULL DEFAULT 0, cache_read_tokens INTEGER NOT NULL DEFAULT 0,
            cache_write_tokens INTEGER NOT NULL DEFAULT 0, output_tokens INTEGER NOT NULL DEFAULT 0,
            cost_usd REAL NOT NULL DEFAULT 0, kept INTEGER, dropped INTEGER,
            CHECK((outcome = 'running') = (ended_at IS NULL)), CHECK((outcome = 'failed') = (error IS NOT NULL)))
        """,
        "CREATE INDEX run_started ON run(started_at)",
        """
        CREATE TABLE prompt(
            hash TEXT PRIMARY KEY, task TEXT NOT NULL CHECK(task <> ''), instructions TEXT NOT NULL,
            schema TEXT NOT NULL, first_used TEXT NOT NULL)
        """,
        // What capture keeps. `page` is a page's visible text from the browser extension; `text` is a window's
        // Accessibility text.
        """
        CREATE TABLE activity(
            id INTEGER PRIMARY KEY, ts TEXT NOT NULL,
            kind TEXT NOT NULL CHECK(kind IN ('window','text','page','idle','active','skipped','file','sleep','wake')),
            app TEXT NOT NULL, bundle_id TEXT NOT NULL, title TEXT NOT NULL, document TEXT, text TEXT,
            CHECK(kind IN ('window','text','page','file') OR (app = '' AND title = '' AND document IS NULL AND text IS NULL)))
        """,
        "CREATE INDEX activity_ts ON activity(ts)",
        """
        CREATE TABLE recording(
            id INTEGER PRIMARY KEY, app TEXT NOT NULL, bundle_id TEXT NOT NULL, folder TEXT NOT NULL UNIQUE,
            started_at TEXT NOT NULL, ended_at TEXT,
            state TEXT NOT NULL CHECK(state IN ('recording','saved','failed')), error TEXT,
            CHECK((state = 'recording') = (ended_at IS NULL)), CHECK((state = 'failed') = (error IS NOT NULL)))
        """,
        // What machines find, and the founder's marks; the latest mark is an item's state. `asked_with` is the chance
        // the app picked an item to ask about; null for an item it did not pick.
        """
        CREATE TABLE item(
            id INTEGER PRIMARY KEY, task TEXT NOT NULL CHECK(task <> ''), run_id INTEGER NOT NULL REFERENCES run(id),
            day TEXT NOT NULL, scope TEXT NOT NULL, source TEXT NOT NULL, cite_first INTEGER NOT NULL,
            cite_last INTEGER NOT NULL, start_at TEXT NOT NULL, end_at TEXT NOT NULL,
            fields TEXT NOT NULL CHECK(json_valid(fields) AND json_type(fields) = 'object'),
            quote TEXT NOT NULL CHECK(quote <> ''), created_at TEXT NOT NULL,
            asked_with REAL CHECK(asked_with IS NULL OR (asked_with > 0 AND asked_with <= 1)),
            CHECK(end_at >= start_at), CHECK(cite_last >= cite_first))
        """,
        """
        CREATE TABLE mark(
            id INTEGER PRIMARY KEY, item_id INTEGER NOT NULL REFERENCES item(id) ON DELETE CASCADE, ts TEXT NOT NULL,
            state TEXT NOT NULL CHECK(state IN ('proposed','confirmed','rejected')),
            origin TEXT NOT NULL CHECK(origin IN ('voluntary','audit','recheck')),
            asked_with REAL NOT NULL DEFAULT 1 CHECK(asked_with > 0 AND asked_with <= 1))
        """,
        """
        CREATE VIEW item_mark AS SELECT item.*, COALESCE(
            (SELECT state FROM mark WHERE mark.item_id = item.id ORDER BY mark.id DESC LIMIT 1), 'proposed') AS state
        FROM item
        """,
        "CREATE INDEX item_day ON item(task, day, scope)",
        "CREATE INDEX item_run ON item(run_id)",
        "CREATE INDEX mark_item ON mark(item_id, id)",
        // The team and its people, and machines as records a person owns: renamed, edited, paused or deleted by a
        // new change row; the latest change is the machine's state.
        "CREATE TABLE team(id INTEGER PRIMARY KEY, name TEXT NOT NULL CHECK(name <> ''), created_at TEXT NOT NULL)",
        """
        CREATE TABLE member(
            id INTEGER PRIMARY KEY, team_id INTEGER NOT NULL REFERENCES team(id), name TEXT NOT NULL CHECK(name <> ''),
            role TEXT NOT NULL, is_me INTEGER NOT NULL CHECK(is_me IN (0,1)), added_at TEXT NOT NULL, removed_at TEXT)
        """,
        """
        CREATE TABLE machine(
            id INTEGER PRIMARY KEY, task TEXT NOT NULL UNIQUE CHECK(task <> ''), template TEXT NOT NULL,
            created_at TEXT NOT NULL)
        """,
        """
        CREATE TABLE machine_change(
            id INTEGER PRIMARY KEY, machine_id INTEGER NOT NULL REFERENCES machine(id), at TEXT NOT NULL,
            name TEXT NOT NULL CHECK(name <> ''), spec TEXT NOT NULL CHECK(json_valid(spec)),
            state TEXT NOT NULL CHECK(state IN ('active','paused','deleted')))
        """,
        """
        CREATE VIEW machine_now AS SELECT machine.id, machine.task, machine.template, change.name, change.spec,
            change.state FROM machine JOIN machine_change change ON change.id =
            (SELECT MAX(id) FROM machine_change WHERE machine_id = machine.id)
        """,
        // Every decision on a machine's brief, never updated: a trial started, a switch, a rejection, a rollback.
        """
        CREATE TABLE machine_decision(
            id INTEGER PRIMARY KEY, task TEXT NOT NULL CHECK(task <> ''), at TEXT NOT NULL,
            kind TEXT NOT NULL CHECK(kind IN ('trial','promote','reject','rollback')),
            decided_by TEXT NOT NULL CHECK(decided_by IN ('person','proposer','alarm')),
            brief TEXT NOT NULL, parent_brief TEXT NOT NULL, detail TEXT NOT NULL CHECK(json_valid(detail)))
        """,
        // Mochi's proposals and the founder's decisions on them; the latest decision is a proposal's state.
        """
        CREATE TABLE proposal(
            id INTEGER PRIMARY KEY, run_id INTEGER NOT NULL REFERENCES run(id), name TEXT NOT NULL CHECK(name <> ''),
            template TEXT NOT NULL, brief TEXT NOT NULL CHECK(brief <> ''), why TEXT NOT NULL,
            evidence TEXT NOT NULL CHECK(json_valid(evidence)), created_at TEXT NOT NULL,
            view TEXT NOT NULL DEFAULT 'table')
        """,
        """
        CREATE TABLE proposal_decision(
            id INTEGER PRIMARY KEY, proposal_id INTEGER NOT NULL REFERENCES proposal(id) ON DELETE CASCADE,
            decision TEXT NOT NULL CHECK(decision IN ('waiting','accepted','rejected','later')), at TEXT NOT NULL)
        """,
        """
        CREATE VIEW proposal_now AS SELECT proposal.*, COALESCE(
            (SELECT decision FROM proposal_decision WHERE proposal_id = proposal.id ORDER BY id DESC LIMIT 1),
            'waiting') AS decision
        FROM proposal
        """,
        // Who each teammate is in a source (their WhatsApp id), set by the founder; the latest link wins. Every act
        // that leaves the founder's store, logged once. Every event on shared work objects, from every teammate: a
        // union by event id, never updated.
        """
        CREATE TABLE member_handle(
            id INTEGER PRIMARY KEY, member_id INTEGER NOT NULL REFERENCES member(id),
            kind TEXT NOT NULL CHECK(kind IN ('whatsapp')), handle TEXT NOT NULL CHECK(handle <> ''), at TEXT NOT NULL)
        """,
        """
        CREATE TABLE action(
            id INTEGER PRIMARY KEY, at TEXT NOT NULL, kind TEXT NOT NULL CHECK(kind <> ''), target TEXT NOT NULL,
            detail TEXT NOT NULL CHECK(json_valid(detail)))
        """,
        """
        CREATE TABLE work_event(
            id INTEGER PRIMARY KEY, event_id TEXT NOT NULL UNIQUE CHECK(event_id <> ''), object TEXT NOT NULL,
            author TEXT NOT NULL, clock INTEGER NOT NULL, at TEXT NOT NULL,
            kind TEXT NOT NULL CHECK(kind IN ('create','title','stage','note','link','claim','release','archive')),
            body TEXT NOT NULL CHECK(json_valid(body)))
        """,
        "CREATE INDEX work_event_object ON work_event(object)",
    ]
}
