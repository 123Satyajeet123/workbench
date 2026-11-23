import Foundation

extension Schema {
    /// A run may end `cancelled`, and a failed run names its kind of failure. SQLite cannot change a CHECK, so `run`
    /// is rebuilt by the 12-step procedure. Every old row keeps its values; an old failed row gets the kind `other`,
    /// because its words are not read to guess a kind.
    static let runFailures = [
        """
        CREATE TABLE run_rebuilt(
            id INTEGER PRIMARY KEY, task TEXT NOT NULL CHECK(task <> ''), model TEXT NOT NULL, prompt TEXT NOT NULL,
            input_bytes INTEGER NOT NULL, input_sha TEXT NOT NULL, started_at TEXT NOT NULL, ended_at TEXT,
            outcome TEXT NOT NULL CHECK(outcome IN ('running','done','failed','cancelled')), error TEXT,
            input_tokens INTEGER NOT NULL DEFAULT 0, cache_read_tokens INTEGER NOT NULL DEFAULT 0,
            cache_write_tokens INTEGER NOT NULL DEFAULT 0, output_tokens INTEGER NOT NULL DEFAULT 0,
            cost_usd REAL NOT NULL DEFAULT 0, kept INTEGER, dropped INTEGER,
            failure TEXT CHECK(failure IN ('limit','timedOut','notInstalled','noAPIKey','unsafePlan','other')),
            CHECK((outcome = 'running') = (ended_at IS NULL)), CHECK((outcome = 'failed') = (error IS NOT NULL)),
            CHECK((outcome = 'failed') = (failure IS NOT NULL)))
        """,
        """
        INSERT INTO run_rebuilt(id, task, model, prompt, input_bytes, input_sha, started_at, ended_at, outcome, error,
            input_tokens, cache_read_tokens, cache_write_tokens, output_tokens, cost_usd, kept, dropped, failure)
        SELECT id, task, model, prompt, input_bytes, input_sha, started_at, ended_at, outcome, error, input_tokens,
            cache_read_tokens, cache_write_tokens, output_tokens, cost_usd, kept, dropped,
            CASE WHEN outcome = 'failed' THEN 'other' END
        FROM run
        """,
        "DROP TABLE run",
        "ALTER TABLE run_rebuilt RENAME TO run",
        "CREATE INDEX run_started ON run(started_at)",
    ]
}
