import Foundation

extension Schema {
    /// A line whose words were quoted from an earlier message or forwarded is marked at capture: `forwarded` is 1 for
    /// such a line and 0 for the writer's own words. Like every column of a line it never changes. A source with no
    /// sign of its own sets none, so every line before this step stays 0.
    static let evidenceForwarded = [
        "ALTER TABLE evidence ADD COLUMN forwarded INTEGER NOT NULL DEFAULT 0 CHECK(forwarded IN (0,1))",
        "DROP TRIGGER evidence_never_changes",
        """
        CREATE TRIGGER evidence_never_changes BEFORE UPDATE OF id, line_id, entity_key, quality, source_id, container,
            event_time, first_seen, actor, text, reply_to, coordinate, message_ref, tombstone, label_id, grant_id,
            audience_digest, retention_class, obtained_by, walk_complete, reader_version, forwarded ON evidence
        BEGIN SELECT RAISE(ABORT, 'an evidence line never changes'); END
        """,
    ]
}
