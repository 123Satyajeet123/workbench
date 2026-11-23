import Foundation
import GRDB

extension Schema {
    /// A folder keeps the type of the objects it holds (`GalleryTemplate.FolderStart.holds`), so a new object of that
    /// type with no parent goes in it. A folder that a template made before this step gets the type from the machines
    /// whose pages it holds (`giveFoldersTheirTypes`).
    static let folderHolds = [
        "ALTER TABLE work_object ADD COLUMN holds TEXT CHECK(holds IS NULL OR holds <> '')"
    ]

    /// Each folder that holds the page of a machine takes the type that the folder of the machine's template holds, when
    /// it has none yet.
    static func giveFoldersTheirTypes(_ db: Database) throws {
        let machines = try Row.fetchAll(
            db,
            sql: """
                SELECT machine.template, page.parent_id FROM machine JOIN work_object page ON page.id = machine.page_id
                WHERE page.parent_id IS NOT NULL ORDER BY machine.id
                """)
        for machine in machines {
            guard let holds = GalleryTemplate.folder(forMachine: machine["template"]).holds else { continue }
            try WorkObjectRows.setHolds(db, folder: machine["parent_id"], to: holds)
        }
    }
}
