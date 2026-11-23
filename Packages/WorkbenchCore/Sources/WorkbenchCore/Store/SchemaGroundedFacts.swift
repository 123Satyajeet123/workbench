import Foundation

extension Schema {
    /// What a fact rests on, as code computed it (research 59 §5 steps 1 and 2), and why the verifier refused a proposal.
    /// An item keeps where its quote is in the line it came from (`quote_line` is the number of the line, `quote_part`
    /// which of its quotable texts, `quote_start` and `quote_end` the offsets in Unicode scalars, the end past the last
    /// character), its `label` (the join of the labels of what it cites, as JSON; null when not known), and its
    /// `authority` (no more than the least trusted line it rests on; `unknown` for a model item that existed before this
    /// step, and `own_words` for a typed one). A drop-reason row is one proposal that a reading refused: the list of the reply it came from, its place
    /// in that list, the rule it broke and the proposal as the model wrote it. A row is written once. It depends on the
    /// run's text, because it holds words from that text, so every delete of run text deletes it too.
    static let groundedFacts = [
        "ALTER TABLE item ADD COLUMN quote_line INTEGER",
        "ALTER TABLE item ADD COLUMN quote_part INTEGER CHECK(quote_part IS NULL OR quote_part >= 0)",
        "ALTER TABLE item ADD COLUMN quote_start INTEGER CHECK(quote_start IS NULL OR quote_start >= 0)",
        "ALTER TABLE item ADD COLUMN quote_end INTEGER CHECK(quote_end IS NULL OR quote_end > 0)",
        "ALTER TABLE item ADD COLUMN label TEXT CHECK(label IS NULL OR (json_valid(label) AND json_type(label) = 'object'))",
        """
        ALTER TABLE item ADD COLUMN authority TEXT NOT NULL DEFAULT 'unknown'
            CHECK(authority IN ('unknown','forwarded_or_quoted','group_member','own_words'))
        """,
        "UPDATE item SET authority = 'own_words' WHERE source = 'typed'",
        """
        CREATE TABLE drop_reason(
            id INTEGER PRIMARY KEY, run_id INTEGER NOT NULL REFERENCES run_text(run_id) ON DELETE CASCADE,
            part TEXT NOT NULL CHECK(part <> ''), ordinal INTEGER NOT NULL CHECK(ordinal >= 0),
            rule TEXT NOT NULL CHECK(rule <> ''), proposal TEXT NOT NULL CHECK(json_valid(proposal)),
            UNIQUE(run_id, part, ordinal))
        """,
        """
        CREATE TRIGGER drop_reason_never_changes BEFORE UPDATE ON drop_reason
        BEGIN SELECT RAISE(ABORT, 'a drop reason never changes'); END
        """,
    ]
}
