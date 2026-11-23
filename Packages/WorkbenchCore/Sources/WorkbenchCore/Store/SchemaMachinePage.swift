import Foundation

extension Schema {
    /// What a machine puts on a page, and what it asked for. A machine never writes a block: it writes a proposal, and
    /// the person accepts or discards it. `page_proposal` is one request and what the machine answered. Its `ops` name
    /// block ids only, so the words of a proposal live in one place, `machine_block`, and its `note` (the table
    /// `proposal` is Mochi's). The blocks of a pending proposal are rows with the state `proposed`, outside the page
    /// order; accept makes them `live`, and a block that a new one replaced stays as `replaced`. A proposal has one
    /// request, a typed evidence line. `machine_block_cite` says which lines a block rests on, so the one erase of
    /// copies finds every block built on a line, in every state, and empties its words (`words_erased`). A cite of a
    /// fact keeps the fact and the span of its quote; any other cite is a whole line. `label` is who may read the
    /// block, as JSON, joined from the lines it cites; it is null for a block that holds no words of its own. A page
    /// has at most one pending proposal. The page order is the one `container_order` of the page's work object. A
    /// block the person took off the page has the surface they did it on (`removed_surface`); one that a proposal
    /// removed has none, because the proposal has it.
    static let machinePage = [
        """
        CREATE TABLE page_proposal(
            id INTEGER PRIMARY KEY, object_id TEXT NOT NULL REFERENCES work_object(id),
            machine_id INTEGER NOT NULL REFERENCES machine(id), run_id INTEGER NOT NULL REFERENCES run(id),
            request_line BLOB NOT NULL CHECK(length(request_line) = 32), note TEXT NOT NULL,
            ops TEXT NOT NULL CHECK(json_valid(ops) AND json_type(ops) = 'array'),
            state TEXT NOT NULL CHECK(state IN ('pending','accepted','discarded')), at TEXT NOT NULL,
            decided_at TEXT, surface TEXT,
            CHECK((state = 'pending') = (surface IS NULL)), CHECK((state = 'pending') = (decided_at IS NULL)))
        """,
        "CREATE UNIQUE INDEX page_proposal_one_pending ON page_proposal(object_id) WHERE state = 'pending'",
        "CREATE INDEX page_proposal_request ON page_proposal(request_line)",
        """
        CREATE TABLE machine_block(
            id TEXT PRIMARY KEY CHECK(id <> ''), object_id TEXT NOT NULL REFERENCES work_object(id),
            entity_key BLOB NOT NULL UNIQUE CHECK(length(entity_key) > 0),
            kind TEXT NOT NULL CHECK(kind IN ('heading','text','facts','grid','picker')),
            spec TEXT NOT NULL CHECK(json_valid(spec) AND json_type(spec) = 'object'),
            state TEXT NOT NULL CHECK(state IN ('proposed','live','replaced','removed')),
            made_by_run INTEGER REFERENCES run(id), proposal_id INTEGER REFERENCES page_proposal(id),
            words_erased INTEGER NOT NULL DEFAULT 0 CHECK(words_erased IN (0, 1)),
            removed_surface TEXT CHECK(removed_surface IS NULL OR state = 'removed'),
            label TEXT CHECK(label IS NULL OR (json_valid(label) AND json_type(label) = 'object')),
            made_at TEXT NOT NULL)
        """,
        "CREATE INDEX machine_block_page ON machine_block(object_id, state)",
        "CREATE INDEX machine_block_proposal ON machine_block(proposal_id)",
        """
        CREATE TABLE machine_block_cite(
            block_id TEXT NOT NULL REFERENCES machine_block(id) ON DELETE CASCADE,
            position INTEGER NOT NULL CHECK(position >= 0), item_id INTEGER REFERENCES item(id) ON DELETE SET NULL,
            line_id BLOB NOT NULL CHECK(length(line_id) = 32), quote_start INTEGER CHECK(quote_start >= 0),
            quote_end INTEGER CHECK(quote_end > 0), PRIMARY KEY(block_id, position),
            CHECK((quote_start IS NULL) = (quote_end IS NULL)))
        """,
        "CREATE INDEX machine_block_cite_line ON machine_block_cite(line_id)",
        "CREATE INDEX machine_block_cite_item ON machine_block_cite(item_id)",
    ]
}
