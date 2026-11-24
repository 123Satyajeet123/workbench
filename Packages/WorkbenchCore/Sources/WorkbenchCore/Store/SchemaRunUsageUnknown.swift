import Foundation

extension Schema {
    /// A run's tokens and cost may be unknown: a call killed on a time-out has no result line to count them from, and
    /// NULL says so where 0 would say the call was free. SQLite cannot drop a NOT NULL, so `run` is rebuilt by the
    /// 12-step procedure with the five columns nullable and no default. An old run that failed or was cancelled
    /// never had its usage written, so its 0 becomes NULL; every other value stays.
    static let runUsageUnknown = [
        """
        CREATE TABLE run_rebuilt(
            id INTEGER PRIMARY KEY, task TEXT NOT NULL CHECK(task <> ''), model TEXT NOT NULL, prompt TEXT NOT NULL,
            input_bytes INTEGER NOT NULL, input_sha TEXT NOT NULL, started_at TEXT NOT NULL, ended_at TEXT,
            outcome TEXT NOT NULL CHECK(outcome IN ('running','done','failed','cancelled')), error TEXT,
            input_tokens INTEGER, cache_read_tokens INTEGER, cache_write_tokens INTEGER, output_tokens INTEGER,
            cost_usd REAL, kept INTEGER, dropped INTEGER,
            failure TEXT CHECK(failure IN ('limit','timedOut','notInstalled','noAPIKey','unsafePlan','other')),
            CHECK((outcome = 'running') = (ended_at IS NULL)), CHECK((outcome = 'failed') = (error IS NOT NULL)),
            CHECK((outcome = 'failed') = (failure IS NOT NULL)))
        """,
        """
        INSERT INTO run_rebuilt(id, task, model, prompt, input_bytes, input_sha, started_at, ended_at, outcome, error,
            input_tokens, cache_read_tokens, cache_write_tokens, output_tokens, cost_usd, kept, dropped, failure)
        SELECT id, task, model, prompt, input_bytes, input_sha, started_at, ended_at, outcome, error,
            CASE WHEN outcome = 'done' THEN input_tokens END, CASE WHEN outcome = 'done' THEN cache_read_tokens END,
            CASE WHEN outcome = 'done' THEN cache_write_tokens END, CASE WHEN outcome = 'done' THEN output_tokens END,
            CASE WHEN outcome = 'done' THEN cost_usd END, kept, dropped, failure
        FROM run
        """,
        "DROP TABLE run",
        "ALTER TABLE run_rebuilt RENAME TO run",
        "CREATE INDEX run_started ON run(started_at)",
    ]
}
