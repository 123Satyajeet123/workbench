import Foundation

extension Schema {
    /// What a derived thing rests on, as one record (research 86 §5). `run_input` is the shown set of a run: what the
    /// model was shown, one row per item, in the order it was shown (`ordinal` is the number in front of it). `ref` is
    /// the line id of a line, or the id of the fact, example, block or snapshot. A row is written once; a revoke moves
    /// the `ref` of a line to its tombstone, and deleting a line or a run deletes its rows. New runs write here;
    /// `run_window` keeps the rows of runs before this step until the backfill moves them, and `run_line` reads both.
    /// `derivation` holds one edge for each thing a node that lives outside a run was made from. `quotes` says the node
    /// holds words copied from the source; `supports` says the node rests on the source. A row is written once and
    /// never changes; a revoke moves a line to its tombstone, and a delete removes it. The primary key is the index by
    /// node; the second index finds the nodes of a source, which is how an erase finds every copy. `rule` names what
    /// made the edge. The words of a run are reached through `run_input`, and the words of every other node through
    /// `derivation`. A work product and a verdict may lose their words and nothing else, so an erase can put the marker `[erased]` in them, and in a drop reason, and nothing else.
    static let provenance = [
        """
        CREATE TABLE run_input(
            run_id INTEGER NOT NULL REFERENCES run(id) ON DELETE CASCADE,
            ordinal INTEGER NOT NULL,
            kind TEXT NOT NULL CHECK(kind IN ('line','fact','example','block','snapshot')),
            ref ANY NOT NULL CHECK((kind = 'line') = (typeof(ref) = 'blob' AND length(ref) = 32)),
            PRIMARY KEY(run_id, ordinal)
        ) STRICT, WITHOUT ROWID
        """,
        "CREATE INDEX run_input_ref ON run_input(ref, kind)",
        """
        CREATE TRIGGER run_input_written_once BEFORE INSERT ON run_input
        BEGIN SELECT CASE
            WHEN EXISTS (SELECT 1 FROM run_input WHERE run_id = NEW.run_id AND ordinal = NEW.ordinal
                AND (kind IS NOT NEW.kind OR ref IS NOT NEW.ref)) THEN RAISE(ABORT, 'a run input never changes')
            WHEN EXISTS (SELECT 1 FROM run_input WHERE run_id = NEW.run_id AND ordinal = NEW.ordinal)
                THEN RAISE(IGNORE)
        END; END
        """,
        """
        CREATE TRIGGER run_input_never_changes BEFORE UPDATE OF run_id, ordinal, kind ON run_input
        BEGIN SELECT RAISE(ABORT, 'a run input never changes'); END
        """,
        """
        CREATE TRIGGER run_input_only_a_revoke_moves_a_line BEFORE UPDATE OF ref ON run_input
        WHEN NOT EXISTS (
            SELECT 1 FROM evidence tombstone WHERE tombstone.line_id = NEW.ref AND tombstone.tombstone = 1
                AND tombstone.container = (SELECT container FROM evidence WHERE line_id = OLD.ref))
        BEGIN SELECT RAISE(ABORT, 'only a revoke moves a run input line to its tombstone'); END
        """,
        """
        CREATE TRIGGER run_input_goes_with_its_line AFTER DELETE ON evidence
        BEGIN DELETE FROM run_input WHERE kind = 'line' AND ref = OLD.line_id; END
        """,
        """
        CREATE VIEW run_line AS SELECT run_id, ordinal, ref AS line_id FROM run_input WHERE kind = 'line'
            UNION ALL SELECT run_id, ordinal, line_id FROM run_window
        """,
        """
        CREATE TABLE derivation(
            node_kind TEXT NOT NULL CHECK(node_kind <> ''), node_id ANY NOT NULL,
            from_kind TEXT NOT NULL CHECK(from_kind <> ''), from_id ANY NOT NULL,
            edge TEXT NOT NULL CHECK(edge IN ('quotes','supports')), run_id INTEGER, rule TEXT NOT NULL,
            recorded_at TEXT NOT NULL, PRIMARY KEY(node_kind, node_id, from_kind, from_id, edge)
        ) STRICT, WITHOUT ROWID
        """,
        "CREATE INDEX derivation_from ON derivation(from_kind, from_id)",
        """
        CREATE TRIGGER derivation_never_changes BEFORE UPDATE ON derivation
        WHEN NOT (OLD.from_kind = 'line' AND NEW.from_kind = 'line' AND NEW.node_kind IS OLD.node_kind
            AND NEW.node_id IS OLD.node_id AND NEW.edge IS OLD.edge AND NEW.run_id IS OLD.run_id
            AND NEW.rule IS OLD.rule AND NEW.recorded_at IS OLD.recorded_at AND EXISTS (
                SELECT 1 FROM evidence tombstone WHERE tombstone.line_id = NEW.from_id AND tombstone.tombstone = 1
                    AND tombstone.container = (SELECT container FROM evidence WHERE line_id = OLD.from_id)))
        BEGIN SELECT RAISE(ABORT, 'a derivation edge never changes except the move of a revoked line'); END
        """,
        """
        CREATE TRIGGER derivation_goes_with_its_line AFTER DELETE ON evidence
        BEGIN DELETE FROM derivation WHERE from_kind = 'line' AND from_id = OLD.line_id; END
        """,
        "DROP TRIGGER work_product_never_changes",
        """
        CREATE TRIGGER work_product_never_changes BEFORE UPDATE ON work_product
        WHEN NOT (NEW.text = '[erased]' AND NEW.id IS OLD.id AND NEW.task_type IS OLD.task_type
            AND NEW.object_id IS OLD.object_id AND NEW.subject IS OLD.subject AND NEW.run_id IS OLD.run_id
            AND NEW.source IS OLD.source AND NEW.created_at IS OLD.created_at AND NEW.split_role IS OLD.split_role
            AND NEW.catch_chance IS OLD.catch_chance AND NEW.versions IS OLD.versions)
        BEGIN SELECT RAISE(ABORT, 'a work product never changes except the erase of its text'); END
        """,
        "DROP TRIGGER judge_verdict_never_changes",
        """
        CREATE TRIGGER judge_verdict_never_changes BEFORE UPDATE ON judge_verdict
        WHEN NOT (NEW.reason = '[erased]' AND NEW.detail = '[erased]' AND NEW.id IS OLD.id
            AND NEW.product_id IS OLD.product_id AND NEW.claim_id IS OLD.claim_id AND NEW.stage IS OLD.stage
            AND NEW.rubric_item IS OLD.rubric_item AND NEW.verdict IS OLD.verdict AND NEW.score IS OLD.score
            AND NEW.versions IS OLD.versions AND NEW.run_id IS OLD.run_id AND NEW.created_at IS OLD.created_at)
        BEGIN SELECT RAISE(ABORT, 'a verdict never changes except the erase of its words'); END
        """,
        "DROP TRIGGER drop_reason_never_changes",
        """
        CREATE TRIGGER drop_reason_never_changes BEFORE UPDATE ON drop_reason
        WHEN NOT (NEW.proposal = '"[erased]"' AND NEW.id IS OLD.id AND NEW.run_id IS OLD.run_id
            AND NEW.part IS OLD.part AND NEW.ordinal IS OLD.ordinal AND NEW.rule IS OLD.rule)
        BEGIN SELECT RAISE(ABORT, 'a drop reason never changes except the erase of its words'); END
        """,
    ]
}
