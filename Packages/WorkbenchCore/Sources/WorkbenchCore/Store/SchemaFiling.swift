import Foundation

extension Schema {
    /// The tree of the workspace, and a home for every fact (research 73 §2.4). One store is one workspace, so no row
    /// names a workspace. `work_object` holds every node of the tree: a folder, a page, a machine's page, a deal, a
    /// project. A node has one parent and a position among its siblings; an archived node leaves the tree. A deal keeps
    /// its stage moves, notes, claims and links as events in `work_event`; its row holds its place and its name.
    /// `machine.page_id` points a machine to its page, whose parent is the folder the machine serves, so a machine
    /// lives in one folder. `fact_link` files a fact under a node: a row is written once and never changes, and the
    /// latest row of a fact, by time and then by id, is its one home (`fact_home`). A model's proposal, a person's
    /// confirmation and a person's move are rows of their own. A row of a person has the surface it was made on, as
    /// every mark of a person does. `machine_now` also gives the page of the machine.
    static let filing = [
        """
        CREATE TABLE work_object(
            id TEXT PRIMARY KEY CHECK(id <> ''), type TEXT NOT NULL CHECK(type <> ''),
            parent_id TEXT REFERENCES work_object(id), position REAL NOT NULL, name TEXT NOT NULL,
            archived_at TEXT, CHECK(parent_id IS NULL OR parent_id <> id))
        """,
        "CREATE INDEX work_object_parent ON work_object(parent_id, position)",
        "ALTER TABLE machine ADD COLUMN page_id TEXT REFERENCES work_object(id)",
        "DROP VIEW machine_now",
        """
        CREATE VIEW machine_now AS SELECT machine.id, machine.task, machine.template, machine.page_id, change.name,
            change.spec, change.state FROM machine JOIN machine_change change ON change.id =
            (SELECT MAX(id) FROM machine_change WHERE machine_id = machine.id)
        """,
        """
        CREATE TABLE fact_link(
            id INTEGER PRIMARY KEY, item_id INTEGER NOT NULL REFERENCES item(id) ON DELETE CASCADE,
            object_id TEXT NOT NULL REFERENCES work_object(id),
            how TEXT NOT NULL CHECK(how IN ('machineFolder','origin','modelProposed','personConfirmed','personMoved')),
            at TEXT NOT NULL, surface TEXT,
            CHECK((how IN ('personConfirmed','personMoved')) = (surface IS NOT NULL)))
        """,
        "CREATE INDEX fact_link_item ON fact_link(item_id, at, id)",
        "CREATE INDEX fact_link_object ON fact_link(object_id)",
        """
        CREATE TRIGGER fact_link_never_changes BEFORE UPDATE ON fact_link
        BEGIN SELECT RAISE(ABORT, 'a filing never changes'); END
        """,
        """
        CREATE VIEW fact_home AS SELECT item_id, object_id, how, at, surface
        FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY item_id ORDER BY at DESC, id DESC) AS rank FROM fact_link)
        WHERE rank = 1
        """,
    ]
}
