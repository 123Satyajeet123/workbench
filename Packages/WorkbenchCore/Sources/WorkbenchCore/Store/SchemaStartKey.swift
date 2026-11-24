import Foundation
import GRDB

extension Schema {
    /// A folder that a template made carries the key of its `FolderStart`, so a start finds it again whatever the
    /// person renamed it. The index holds one live key per parent; a team is a folder with a team key
    /// (`FolderTree.teamKey`). A folder that a template made before this step gets its key from structure
    /// (`giveFoldersTheirKeys`); no existing folder becomes a team.
    static let startKey = [
        "ALTER TABLE work_object ADD COLUMN start_key TEXT CHECK(start_key IS NULL OR start_key <> '')",
        """
        CREATE UNIQUE INDEX work_object_start_key ON work_object(COALESCE(parent_id, ''), start_key)
        WHERE start_key IS NOT NULL
        """,
    ]

    /// Gives keys to the folders that exist, and changes nothing else: no row is added, deleted or moved, no name
    /// changes. Two rules, each leaving a folder with no key rather than guess:
    /// - a live folder that holds the page of a machine takes the key of the folder of the machine's template, when it
    ///   has no key and no sibling has that key (the first machine by id decides);
    /// - a live root folder that holds no machine page and has exactly the name of a template's folder takes that key,
    ///   when it is the only such root folder and no root folder has the key.
    static func giveFoldersTheirKeys(_ db: Database) throws {
        let machines = try Row.fetchAll(
            db,
            sql: """
                SELECT machine.template, page.parent_id FROM machine JOIN work_object page ON page.id = machine.page_id
                WHERE page.parent_id IS NOT NULL ORDER BY machine.id
                """)
        for machine in machines {
            try setKey(
                db, folder: machine["parent_id"], to: GalleryTemplate.folder(forMachine: machine["template"]).key)
        }
        let starts = GalleryTemplate.all.map(\.folder)
        let roots = try Row.fetchAll(
            db,
            sql: """
                SELECT id, name FROM work_object root WHERE type = ? AND parent_id IS NULL AND archived_at IS NULL
                    AND start_key IS NULL
                    AND NOT EXISTS(SELECT 1 FROM machine JOIN work_object page ON page.id = machine.page_id
                        WHERE page.parent_id = root.id)
                """, arguments: [ObjectTypes.folder.id])
        for start in starts {
            let named = roots.filter { ($0["name"] as String) == start.name }
            if named.count == 1 { try setKey(db, folder: named[0]["id"], to: start.key) }
        }
    }

    /// The folder takes `key` when it has none, is not archived, and no live sibling carries the key.
    private static func setKey(_ db: Database, folder: WorkObjectID, to key: String) throws {
        try db.execute(
            sql: """
                UPDATE work_object SET start_key = ?1 WHERE id = ?2 AND start_key IS NULL AND archived_at IS NULL
                    AND NOT EXISTS(SELECT 1 FROM work_object sibling WHERE sibling.start_key = ?1
                        AND COALESCE(sibling.parent_id, '') = COALESCE(work_object.parent_id, ''))
                """, arguments: [key, folder])
    }
}
