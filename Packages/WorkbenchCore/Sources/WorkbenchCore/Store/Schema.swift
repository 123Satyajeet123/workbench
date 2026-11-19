import Foundation

/// The schema of `workbench.sqlite` as an append-only list of steps. `user_version` counts the steps a store has run;
/// opening a store runs the steps it lacks, in one transaction. A shipped step never changes (`SchemaTests` pins each
/// one's digest), so a step is literal text, never built from a Swift enum: a new need is a new step. A store from a newer Workbench is refused.
enum Schema {
    static var version: Int32 { Int32(steps.count) }

    static func open(_ database: Database) throws {
        let found = Int(try database.rows("PRAGMA user_version").first?.first?.integer ?? 0)
        guard found <= steps.count else { throw SchemaError.newerVersion }
        guard found < steps.count else { return }
        try database.transaction {
            for statement in steps[found...].joined() { try database.run(statement) }
            try database.run("PRAGMA user_version = \(version)")
        }
    }

    static var stepDigests: [String] { steps.map { Digest.sha256($0.joined(separator: ";\n")) } }

    static let steps = [base, timeline, prompts, items, audit, crew, proposals, proposalView]

    private static let base = [
        "CREATE TABLE IF NOT EXISTS state(key TEXT PRIMARY KEY, value TEXT NOT NULL, saved_at TEXT NOT NULL)",
        "CREATE TABLE IF NOT EXISTS consent(id INTEGER PRIMARY KEY, ts TEXT NOT NULL, policy TEXT NOT NULL)",
        """
        CREATE TABLE IF NOT EXISTS run(
            id INTEGER PRIMARY KEY, task TEXT NOT NULL CHECK(task <> ''), model TEXT NOT NULL, prompt TEXT NOT NULL,
            input_bytes INTEGER NOT NULL, input_sha TEXT NOT NULL, started_at TEXT NOT NULL, ended_at TEXT,
            outcome TEXT NOT NULL CHECK(outcome IN ('running','done','failed')), error TEXT,
            input_tokens INTEGER NOT NULL DEFAULT 0, cache_read_tokens INTEGER NOT NULL DEFAULT 0,
            cache_write_tokens INTEGER NOT NULL DEFAULT 0, output_tokens INTEGER NOT NULL DEFAULT 0,
            cost_usd REAL NOT NULL DEFAULT 0, kept INTEGER, dropped INTEGER,
            CHECK((outcome = 'running') = (ended_at IS NULL)), CHECK((outcome = 'failed') = (error IS NOT NULL)))
        """,
        "CREATE INDEX IF NOT EXISTS run_started ON run(started_at)",
        """
        CREATE TABLE IF NOT EXISTS activity(
            id INTEGER PRIMARY KEY, ts TEXT NOT NULL,
            kind TEXT NOT NULL CHECK(kind IN ('window','text','idle','active','skipped','file','sleep','wake')),
            app TEXT NOT NULL, bundle_id TEXT NOT NULL, title TEXT NOT NULL, document TEXT, text TEXT,
            CHECK(kind IN ('window','text','file') OR (app = '' AND title = '' AND document IS NULL AND text IS NULL)))
        """,
        "CREATE INDEX IF NOT EXISTS activity_ts ON activity(ts)",
        """
        CREATE TABLE IF NOT EXISTS recording(
            id INTEGER PRIMARY KEY, app TEXT NOT NULL, bundle_id TEXT NOT NULL, folder TEXT NOT NULL UNIQUE,
            started_at TEXT NOT NULL, ended_at TEXT,
            state TEXT NOT NULL CHECK(state IN ('recording','saved','failed')), error TEXT,
            CHECK((state = 'recording') = (ended_at IS NULL)), CHECK((state = 'failed') = (error IS NOT NULL)))
        """,
        """
        CREATE TABLE IF NOT EXISTS ledger_entry(
            id INTEGER PRIMARY KEY, run_id INTEGER NOT NULL REFERENCES run(id),
            chat TEXT NOT NULL, day TEXT NOT NULL, person TEXT NOT NULL,
            kind TEXT NOT NULL CHECK(kind IN ('plan','done','blocker')),
            text TEXT NOT NULL, eta TEXT NOT NULL, quote TEXT NOT NULL CHECK(quote <> ''),
            message_id INTEGER NOT NULL, said_at TEXT NOT NULL,
            state TEXT NOT NULL CHECK(state IN ('proposed','confirmed','rejected')), created_at TEXT NOT NULL)
        """,
        "CREATE INDEX IF NOT EXISTS ledger_day ON ledger_entry(chat, day)",
        "CREATE INDEX IF NOT EXISTS ledger_run ON ledger_entry(run_id)",
    ]

    private static let timeline = [
        """
        CREATE TABLE timeline_block(
            id INTEGER PRIMARY KEY, run_id INTEGER NOT NULL REFERENCES run(id), day TEXT NOT NULL,
            start_at TEXT NOT NULL, end_at TEXT NOT NULL, task TEXT NOT NULL CHECK(task <> ''), project TEXT NOT NULL,
            quote TEXT NOT NULL CHECK(quote <> ''), state TEXT NOT NULL CHECK(state IN ('proposed','confirmed','rejected')),
            created_at TEXT NOT NULL, CHECK(end_at > start_at))
        """,
        "CREATE INDEX timeline_day ON timeline_block(day)",
        "CREATE INDEX timeline_run ON timeline_block(run_id)",
    ]

    private static let prompts = [
        """
        CREATE TABLE prompt(
            hash TEXT PRIMARY KEY, task TEXT NOT NULL CHECK(task <> ''), instructions TEXT NOT NULL,
            schema TEXT NOT NULL, first_used TEXT NOT NULL)
        """
    ]

    private static let items = [
        """
        CREATE TABLE item(
            id INTEGER PRIMARY KEY, task TEXT NOT NULL CHECK(task <> ''), run_id INTEGER NOT NULL REFERENCES run(id),
            day TEXT NOT NULL, scope TEXT NOT NULL, source TEXT NOT NULL, cite_first INTEGER NOT NULL,
            cite_last INTEGER NOT NULL, start_at TEXT NOT NULL, end_at TEXT NOT NULL,
            fields TEXT NOT NULL CHECK(json_valid(fields) AND json_type(fields) = 'object'),
            quote TEXT NOT NULL CHECK(quote <> ''), created_at TEXT NOT NULL,
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
        """
        INSERT INTO item(task, run_id, day, scope, source, cite_first, cite_last, start_at, end_at, fields, quote,
            created_at)
        SELECT 'team.ledger', run_id, day, chat, 'whatsapp', message_id, message_id, said_at, said_at,
            json_object('person', person, 'kind', kind, 'text', text, 'eta', eta), quote, created_at
        FROM ledger_entry ORDER BY id
        """,
        """
        INSERT INTO mark(item_id, ts, state, origin)
        SELECT item.id, l.created_at, l.state, 'voluntary' FROM ledger_entry l JOIN item ON item.task = 'team.ledger'
            AND item.run_id = l.run_id AND item.cite_first = l.message_id AND item.quote = l.quote
            AND item.created_at = l.created_at
        WHERE l.state <> 'proposed'
        """,
        """
        INSERT INTO item(task, run_id, day, scope, source, cite_first, cite_last, start_at, end_at, fields, quote,
            created_at)
        SELECT 'day.timeline', run_id, day, '', 'screen', 0, 0, start_at, end_at,
            json_object('task', task, 'project', project), quote, created_at
        FROM timeline_block ORDER BY id
        """,
        """
        INSERT INTO mark(item_id, ts, state, origin)
        SELECT item.id, t.created_at, t.state, 'voluntary' FROM timeline_block t JOIN item ON item.task = 'day.timeline'
            AND item.run_id = t.run_id AND item.start_at = t.start_at AND item.quote = t.quote
        WHERE t.state <> 'proposed'
        """,
        "DROP TABLE ledger_entry",
        "DROP TABLE timeline_block",
        "CREATE INDEX item_day ON item(task, day, scope)",
        "CREATE INDEX item_run ON item(run_id)",
        "CREATE INDEX mark_item ON mark(item_id, id)",
    ]

    /// The chance the app picked an item to ask the founder about; null for an item it did not pick.
    private static let audit = [
        "ALTER TABLE item ADD COLUMN asked_with REAL CHECK(asked_with IS NULL OR (asked_with > 0 AND asked_with <= 1))"
    ]

    /// The team and its people, and machines as records a person owns: renamed, edited, paused or deleted by a new
    /// change row; the latest change is the machine's state.
    private static let crew = [
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
    ]

    /// Mochi's proposals and the founder's decisions on them; the latest decision is a proposal's state.
    private static let proposals = [
        """
        CREATE TABLE proposal(
            id INTEGER PRIMARY KEY, run_id INTEGER NOT NULL REFERENCES run(id), name TEXT NOT NULL CHECK(name <> ''),
            template TEXT NOT NULL, brief TEXT NOT NULL CHECK(brief <> ''), why TEXT NOT NULL,
            evidence TEXT NOT NULL CHECK(json_valid(evidence)), created_at TEXT NOT NULL)
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
    ]

    /// The view Mochi chose for a proposed machine.
    private static let proposalView = ["ALTER TABLE proposal ADD COLUMN view TEXT NOT NULL DEFAULT 'table'"]
}
