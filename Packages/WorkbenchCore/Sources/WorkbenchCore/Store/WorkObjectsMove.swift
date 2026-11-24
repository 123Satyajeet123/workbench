import Foundation
import GRDB

/// The one-time move into the tree, run with the filing step in its transaction. It changes no event, no line and no
/// fact. It adds rows: a node for each deal, a project for each note, a page in a folder for each machine, and a home
/// for each fact of a machine.
enum WorkObjectsMove {
    static func run(_ db: Database) throws {
        try WorkObjectRows.project(
            db,
            objects: try String.fetchAll(
                db, sql: "SELECT object FROM work_event GROUP BY object ORDER BY MIN(clock), object"))
        try projectNotes(db)
        try pageMachines(db)
        try FactFiling.fileInDefaultHomes(db, origin: .deal)
    }

    /// A note's lines are written once and name their container, so they cannot move to another container. The
    /// container is the work object: each note that exists becomes a project whose id is its container.
    private static func projectNotes(_ db: Database) throws {
        let containers = try String.fetchAll(
            db,
            sql: "SELECT DISTINCT container FROM evidence WHERE grant_id = ? || container ORDER BY container",
            arguments: [Store.grantID(kind: .note, label: "")])
        for container in containers {
            guard try Int.fetchOne(db, sql: "SELECT 1 FROM work_object WHERE id = ?", arguments: [container]) == nil
            else { continue }
            try WorkObjectRows.insert(db, id: container, type: ObjectTypes.project.id, parent: nil, name: container)
        }
    }

    private static func pageMachines(_ db: Database) throws {
        let machines = try Row.fetchAll(
            db,
            sql: "SELECT id, template, name FROM machine_now WHERE page_id IS NULL AND state <> 'deleted' ORDER BY id"
        )
        for machine in machines {
            try WorkObjectRows.addMachinePage(
                db, machine: machine["id"], template: machine["template"], name: machine["name"], folder: nil)
        }
    }
}
