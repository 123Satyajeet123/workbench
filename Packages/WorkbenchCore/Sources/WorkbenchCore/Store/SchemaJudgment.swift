import Foundation

extension Schema {
    /// The judgment layer (ADR-020). A page snapshot is a fetched page kept once, with the hash of its text and the date
    /// the page states. A work product is one output of a task, written once with its split role; its claims are items
    /// (so marks, audits and the certificate work as they do for every fact), and a claim cites lines or snapshots by
    /// span. `judge_verdict` is the one trace table: a row per stage, per claim or per rubric item or per product,
    /// with the versions of every part that made it; a later judgment adds rows and never changes one. A mark that
    /// says a claim is unsupported is a `mark` with a reason. A product mark keeps the edited text in full. A freeze
    /// names the parts of a judge by hash, and starts the held-out window of its task; a held-out number is reported
    /// once per freeze.
    static let judgment = [
        """
        CREATE TABLE page_snapshot(
            id INTEGER PRIMARY KEY, url TEXT NOT NULL CHECK(url <> ''), fetched_at TEXT NOT NULL,
            content_hash TEXT NOT NULL CHECK(length(content_hash) = 64), text TEXT NOT NULL CHECK(text <> ''),
            page_date TEXT, UNIQUE(url, content_hash))
        """,
        """
        CREATE TRIGGER page_snapshot_never_changes BEFORE UPDATE ON page_snapshot
        BEGIN SELECT RAISE(ABORT, 'a page snapshot never changes'); END
        """,
        """
        CREATE TABLE work_product(
            id INTEGER PRIMARY KEY, task_type TEXT NOT NULL CHECK(task_type <> ''),
            object_id TEXT NOT NULL REFERENCES work_object(id), subject TEXT NOT NULL, run_id INTEGER NOT NULL REFERENCES run(id), source TEXT NOT NULL,
            text TEXT NOT NULL, created_at TEXT NOT NULL, split_role TEXT NOT NULL CHECK(split_role IN ('dev','held_out')),
            catch_chance REAL NOT NULL CHECK(catch_chance >= 0 AND catch_chance <= 1),
            versions TEXT NOT NULL CHECK(json_valid(versions) AND json_type(versions) = 'object'))
        """,
        """
        CREATE TRIGGER work_product_never_changes BEFORE UPDATE ON work_product
        BEGIN SELECT RAISE(ABORT, 'a work product never changes'); END
        """,
        "CREATE INDEX work_product_object ON work_product(object_id, id)",
        """
        CREATE TABLE product_claim(
            id INTEGER PRIMARY KEY, product_id INTEGER NOT NULL REFERENCES work_product(id) ON DELETE CASCADE,
            ordinal INTEGER NOT NULL, item_id INTEGER NOT NULL REFERENCES item(id) ON DELETE CASCADE,
            shown_as TEXT NOT NULL CHECK(shown_as IN ('real','catch')), catch_kind TEXT, catch_truth TEXT,
            CHECK((shown_as = 'catch') = (catch_kind IS NOT NULL AND catch_truth IS NOT NULL)),
            UNIQUE(product_id, ordinal), UNIQUE(item_id))
        """,
        """
        CREATE TABLE claim_cite(
            id INTEGER PRIMARY KEY, claim_id INTEGER NOT NULL REFERENCES product_claim(id) ON DELETE CASCADE,
            ordinal INTEGER NOT NULL, kind TEXT NOT NULL CHECK(kind IN ('line','page')),
            line_id BLOB CHECK(line_id IS NULL OR length(line_id) = 32),
            snapshot_id INTEGER REFERENCES page_snapshot(id) ON DELETE SET NULL, content_hash TEXT,
            quote TEXT NOT NULL CHECK(quote <> ''), span_start INTEGER, span_end INTEGER,
            CHECK((kind = 'line') = (line_id IS NOT NULL)), CHECK(kind = 'page' OR snapshot_id IS NULL),
            CHECK((span_start IS NULL) = (span_end IS NULL)), UNIQUE(claim_id, ordinal))
        """,
        """
        CREATE TABLE judge_verdict(
            id INTEGER PRIMARY KEY, product_id INTEGER NOT NULL REFERENCES work_product(id) ON DELETE CASCADE,
            claim_id INTEGER REFERENCES product_claim(id) ON DELETE CASCADE,
            stage TEXT NOT NULL CHECK(stage IN ('structure','grounding','quality','product')), rubric_item TEXT,
            verdict TEXT NOT NULL CHECK(verdict IN ('pass','fail','unknown')), reason TEXT NOT NULL,
            detail TEXT NOT NULL, score REAL, versions TEXT NOT NULL CHECK(json_valid(versions)),
            run_id INTEGER REFERENCES run(id), created_at TEXT NOT NULL,
            CHECK((rubric_item IS NOT NULL) = (stage = 'quality')), CHECK(stage <> 'product' OR claim_id IS NULL))
        """,
        """
        CREATE TRIGGER judge_verdict_never_changes BEFORE UPDATE ON judge_verdict
        BEGIN SELECT RAISE(ABORT, 'a verdict never changes'); END
        """,
        "CREATE INDEX judge_verdict_product ON judge_verdict(product_id, id)",
        """
        CREATE VIEW judge_now AS SELECT * FROM judge_verdict WHERE id IN (
            SELECT MAX(id) FROM judge_verdict
            GROUP BY product_id, COALESCE(claim_id, 0), stage, COALESCE(rubric_item, ''))
        """,
        """
        CREATE TABLE mark_reason(
            mark_id INTEGER PRIMARY KEY REFERENCES mark(id) ON DELETE CASCADE,
            reason TEXT NOT NULL CHECK(reason IN ('wrong','unsupported')))
        """,
        """
        CREATE TABLE product_mark(
            id INTEGER PRIMARY KEY, product_id INTEGER NOT NULL REFERENCES work_product(id) ON DELETE CASCADE,
            ts TEXT NOT NULL, state TEXT NOT NULL CHECK(state IN ('use','edit','discard')), edited_text TEXT,
            surface TEXT NOT NULL CHECK(surface <> ''),
            CHECK((state = 'edit') = (edited_text IS NOT NULL AND edited_text <> '')))
        """,
        "CREATE INDEX product_mark_product ON product_mark(product_id, id)",
        """
        CREATE TABLE judge_freeze(
            hash TEXT PRIMARY KEY CHECK(length(hash) = 64), task_type TEXT NOT NULL CHECK(task_type <> ''),
            frozen_at TEXT NOT NULL, window_days INTEGER NOT NULL CHECK(window_days > 0),
            parts TEXT NOT NULL CHECK(json_valid(parts) AND json_type(parts) = 'object'))
        """,
        """
        CREATE TABLE heldout_report(
            hash TEXT PRIMARY KEY REFERENCES judge_freeze(hash), reported_at TEXT NOT NULL,
            numbers TEXT NOT NULL CHECK(json_valid(numbers)))
        """,
    ]
}
