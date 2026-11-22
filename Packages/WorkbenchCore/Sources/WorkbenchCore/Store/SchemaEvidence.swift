import Foundation

extension Schema {
    /// The evidence store of record (research 56 §1, ADR-015). A line is one row, named by its `line_id` (ADR-014).
    /// A row is written once: a second insert of its `line_id` does nothing, and only `last_seen` may move, forward,
    /// by an UPDATE. Times are UTC milliseconds. `id` is the row number that search points at; it never leaves the
    /// store. `audience_digest` names who could read the line at capture; only a screen line (an entity key that starts
    /// with the framed tag `workbench.entity.v1` and the kind `screen`, ADR-014) may lack it. `evidence_view` keeps the order of one read
    /// of a container; `evidence_legacy` maps a citation that names an older row id (a WhatsApp `Z_PK`, an
    /// `activity`, `mail_part` or `news_article` id) to its lines. View and legacy rows are written once and never
    /// change. Search uses FTS5 over `text`; combining marks, ZWJ and ZWNJ stay inside a word. Deleting a line removes
    /// its search entry, its view rows and its legacy rows. `message_ref` is the source's own id of the message in
    /// its container (a WhatsApp stanza id): a tombstone is final, so no text line of the same entity key, or of the
    /// same container and `message_ref`, is written after it.
    static let evidence = [
        """
        CREATE TABLE evidence(
            id INTEGER PRIMARY KEY,
            line_id BLOB NOT NULL UNIQUE CHECK(length(line_id) = 32),
            entity_key BLOB NOT NULL CHECK(length(entity_key) > 0),
            quality TEXT NOT NULL CHECK(quality IN ('stable','derived','ephemeral')),
            source_id BLOB NOT NULL CHECK(length(source_id) = 16),
            container TEXT NOT NULL CHECK(container <> ''),
            event_time INTEGER, first_seen INTEGER NOT NULL, last_seen INTEGER NOT NULL,
            actor TEXT CHECK(actor IS NULL OR actor <> ''),
            text TEXT NOT NULL,
            reply_to BLOB CHECK(reply_to IS NULL OR length(reply_to) > 0),
            coordinate TEXT CHECK(coordinate IS NULL OR coordinate <> ''),
            message_ref TEXT CHECK(message_ref IS NULL OR message_ref <> ''),
            tombstone INTEGER NOT NULL CHECK(tombstone IN (0,1)),
            label_id BLOB NOT NULL CHECK(length(label_id) = 16),
            grant_id TEXT NOT NULL CHECK(grant_id <> ''),
            audience_digest BLOB CHECK(audience_digest IS NULL OR length(audience_digest) = 32),
            retention_class TEXT NOT NULL CHECK(retention_class <> ''),
            obtained_by TEXT NOT NULL CHECK(obtained_by IN
                ('db','api','dom_text','ax_value','ax_title','ax_description','ocr','speech')),
            walk_complete INTEGER CHECK(walk_complete IS NULL OR walk_complete IN (0,1)),
            reader_version TEXT NOT NULL CHECK(reader_version <> ''),
            CHECK(last_seen >= first_seen), CHECK((tombstone = 1) = (text = '')),
            CHECK(audience_digest IS NOT NULL
                OR substr(entity_key, 1, 33) = x'00000013776f726b62656e63682e656e746974792e76310000000673637265656e')
        ) STRICT
        """,
        """
        CREATE TRIGGER evidence_written_once BEFORE INSERT ON evidence
        BEGIN SELECT CASE
            WHEN EXISTS (SELECT 1 FROM evidence WHERE id = NEW.id AND line_id IS NOT NEW.line_id)
                THEN RAISE(ABORT, 'this row number belongs to another line')
            WHEN EXISTS (SELECT 1 FROM evidence WHERE line_id = NEW.line_id) THEN RAISE(IGNORE)
        END; END
        """,
        """
        CREATE TRIGGER evidence_never_changes BEFORE UPDATE OF id, line_id, entity_key, quality, source_id, container,
            event_time, first_seen, actor, text, reply_to, coordinate, message_ref, tombstone, label_id, grant_id,
            audience_digest, retention_class, obtained_by, walk_complete, reader_version ON evidence
        BEGIN SELECT RAISE(ABORT, 'an evidence line never changes'); END
        """,
        """
        CREATE TRIGGER evidence_revoke_is_final BEFORE INSERT ON evidence
        WHEN NEW.tombstone = 0 AND EXISTS (SELECT 1 FROM evidence WHERE tombstone = 1
            AND (entity_key = NEW.entity_key OR (container = NEW.container AND message_ref = NEW.message_ref)))
        BEGIN SELECT RAISE(IGNORE); END
        """,
        "CREATE INDEX evidence_entity ON evidence(entity_key, last_seen)",
        "CREATE INDEX evidence_message ON evidence(container, message_ref)",
        "CREATE INDEX evidence_source ON evidence(source_id, last_seen)",
        "CREATE INDEX evidence_grant ON evidence(grant_id, last_seen)",
        """
        CREATE TRIGGER evidence_last_seen_moves_forward BEFORE UPDATE OF last_seen ON evidence
        WHEN NEW.last_seen < OLD.last_seen BEGIN SELECT RAISE(ABORT, 'last_seen never moves back'); END
        """,
        """
        CREATE TABLE evidence_view(
            view_id BLOB NOT NULL CHECK(length(view_id) = 32), ordinal INTEGER NOT NULL CHECK(ordinal >= 0),
            line_id BLOB NOT NULL REFERENCES evidence(line_id) ON DELETE CASCADE,
            PRIMARY KEY(view_id, ordinal)
        ) STRICT, WITHOUT ROWID
        """,
        "CREATE INDEX evidence_view_line ON evidence_view(line_id)",
        """
        CREATE TRIGGER evidence_view_written_once BEFORE INSERT ON evidence_view
        BEGIN SELECT CASE
            WHEN EXISTS (SELECT 1 FROM evidence_view WHERE view_id = NEW.view_id AND ordinal = NEW.ordinal
                AND line_id IS NOT NEW.line_id) THEN RAISE(ABORT, 'a view never changes')
            WHEN EXISTS (SELECT 1 FROM evidence_view WHERE view_id = NEW.view_id AND ordinal = NEW.ordinal)
                THEN RAISE(IGNORE)
        END; END
        """,
        """
        CREATE TRIGGER evidence_view_never_changes BEFORE UPDATE ON evidence_view
        BEGIN SELECT RAISE(ABORT, 'a view never changes'); END
        """,
        """
        CREATE TABLE evidence_legacy(
            space TEXT NOT NULL CHECK(space IN ('wa_zpk','activity','mail_part','news_article')),
            ref INTEGER NOT NULL, ord INTEGER NOT NULL CHECK(ord >= 0),
            line_id BLOB NOT NULL REFERENCES evidence(line_id) ON DELETE CASCADE,
            PRIMARY KEY(space, ref, ord)
        ) STRICT, WITHOUT ROWID
        """,
        "CREATE INDEX evidence_legacy_line ON evidence_legacy(line_id)",
        """
        CREATE TRIGGER evidence_legacy_written_once BEFORE INSERT ON evidence_legacy
        BEGIN SELECT CASE
            WHEN EXISTS (SELECT 1 FROM evidence_legacy WHERE space = NEW.space AND ref = NEW.ref AND ord = NEW.ord
                AND line_id IS NOT NEW.line_id) THEN RAISE(ABORT, 'a legacy citation is never rewritten')
            WHEN EXISTS (SELECT 1 FROM evidence_legacy WHERE space = NEW.space AND ref = NEW.ref AND ord = NEW.ord)
                THEN RAISE(IGNORE)
        END; END
        """,
        """
        CREATE TRIGGER evidence_legacy_never_changes BEFORE UPDATE ON evidence_legacy
        BEGIN SELECT RAISE(ABORT, 'a legacy citation is never rewritten'); END
        """,
        """
        CREATE VIRTUAL TABLE evidence_fts USING fts5(
            text, content = 'evidence', content_rowid = 'id',
            tokenize = "unicode61 categories 'L* N* Co Mn Mc' tokenchars '\u{200C}\u{200D}'")
        """,
        """
        CREATE TRIGGER evidence_fts_insert AFTER INSERT ON evidence
        BEGIN INSERT INTO evidence_fts(rowid, text) VALUES (new.id, new.text); END
        """,
        """
        CREATE TRIGGER evidence_fts_delete AFTER DELETE ON evidence
        BEGIN INSERT INTO evidence_fts(evidence_fts, rowid, text) VALUES ('delete', old.id, old.text); END
        """,
    ]
}
