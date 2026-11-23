import Foundation
import GRDB

/// What the filing step does to a store, counted on a copy before it runs on the real store. It holds counts and task
/// names, never a word a person said.
public struct WorkObjectsDryRun: Sendable, Equatable {
    /// Nodes in the tree after the move, by type.
    public var objectsByType: [String: Int]
    /// Machines that got a page, by the folder that holds the page.
    public var machinesByFolder: [String: Int]
    /// Notes whose container became a project.
    public var notes: Int
    public var facts: Int
    public var factsFiled: Int
    /// Facts by the way their home was chosen.
    public var factsByHow: [String: Int]
    /// Facts with no home, by task. A task with no machine has no machine folder.
    public var factsUnfiledByTask: [String: Int]

    /// Runs the step on a copy of the store in `directory` and deletes the copy. A copy of a store already at this step
    /// reports what that step did.
    public static func run(onCopyOf directory: URL) throws -> WorkObjectsDryRun {
        try Store.withCopy(of: directory) { try $0.queries.workObjectsMove() }
    }
}

extension Queries {
    func workObjectsMove() throws -> WorkObjectsDryRun {
        try reader.read { db in
            let counts = { (sql: String) throws -> [String: Int] in
                Dictionary(uniqueKeysWithValues: try Row.fetchAll(db, sql: sql).map { ($0[0] as String, $0[1] as Int) })
            }
            let count = { (sql: String) throws -> Int in try Int.fetchOne(db, sql: sql) ?? 0 }
            return WorkObjectsDryRun(
                objectsByType: try counts("SELECT type, COUNT(*) FROM work_object GROUP BY type"),
                machinesByFolder: try counts(
                    """
                    SELECT folder.name, COUNT(*) FROM machine JOIN work_object page ON page.id = machine.page_id
                    JOIN work_object folder ON folder.id = page.parent_id GROUP BY folder.name
                    """),
                notes: try count(
                    "SELECT COUNT(*) FROM work_object WHERE id IN (SELECT container FROM evidence WHERE grant_id = 'note:' || container)"
                ),
                facts: try count("SELECT COUNT(*) FROM item"),
                factsFiled: try count("SELECT COUNT(DISTINCT item_id) FROM fact_link"),
                factsByHow: try counts("SELECT how, COUNT(*) FROM fact_home GROUP BY how"),
                factsUnfiledByTask: try counts(
                    "SELECT task, COUNT(*) FROM item WHERE id NOT IN (SELECT item_id FROM fact_link) GROUP BY task"))
        }
    }
}
