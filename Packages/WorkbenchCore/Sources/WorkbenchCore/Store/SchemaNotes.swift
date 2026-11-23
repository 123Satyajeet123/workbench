import Foundation

extension Schema {
    /// The structure of a container, which lines do not hold because a line never changes. `container_order` is the order
    /// of the current entities of a container; it is replaced at each write that gives one. `entity_supersede` says that
    /// an entity went on as another (the words of a paragraph joined to the one before it): it is written once and never
    /// changes, and a reader of current lines skips the entity it names. Both hold keys, never words, and a row goes when
    /// the text lines of its entity are erased.
    static let notes = [
        """
        CREATE TABLE container_order(
            container TEXT NOT NULL CHECK(container <> ''), position INTEGER NOT NULL CHECK(position >= 0),
            entity_key BLOB NOT NULL UNIQUE CHECK(length(entity_key) > 0), PRIMARY KEY(container, position)
        ) STRICT, WITHOUT ROWID
        """,
        """
        CREATE TABLE entity_supersede(
            entity_key BLOB PRIMARY KEY CHECK(length(entity_key) > 0),
            into_key BLOB NOT NULL CHECK(length(into_key) > 0 AND into_key <> entity_key), at INTEGER NOT NULL
        ) STRICT, WITHOUT ROWID
        """,
        "CREATE INDEX entity_supersede_into ON entity_supersede(into_key)",
        """
        CREATE TRIGGER entity_supersede_never_changes BEFORE UPDATE ON entity_supersede
        BEGIN SELECT RAISE(ABORT, 'a supersession never changes'); END
        """,
    ]
}
