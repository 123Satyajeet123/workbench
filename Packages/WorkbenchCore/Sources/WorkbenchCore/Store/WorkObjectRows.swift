import Foundation
import GRDB

/// One row of `work_object`: the node of the tree, before the events of a shared object are folded into it.
struct WorkObjectRow: Equatable {
    var id: WorkObjectID
    var type: TypeID
    var parentID: WorkObjectID?
    var position: Double
    var name: String
    var archivedAt: Date?

    static let columns = "id, type, parent_id, position, name, archived_at"

    init(id: WorkObjectID, type: TypeID, parentID: WorkObjectID?, position: Double, name: String, archivedAt: Date?) {
        self.id = id
        self.type = type
        self.parentID = parentID
        self.position = position
        self.name = name
        self.archivedAt = archivedAt
    }

    init(row: Row) throws {
        self.init(
            id: try row.value("id"), type: try row.value("type"), parentID: try row.optionalValue("parent_id"),
            position: try row.value("position"), name: try row.value("name"),
            archivedAt: try row.optionalDate("archived_at"))
    }
}

/// The writes of `work_object` that run inside a transaction already open, for the store's writers and for the step
/// that moves the old data.
enum WorkObjectRows {
    /// Adds a node as the last child of `parent`, or of its place (`place(_:type:madeBy:)`) when it has no parent.
    @discardableResult
    static func insert(
        _ db: Database, id: WorkObjectID = UUID().uuidString, type: TypeID, parent: WorkObjectID?, name: String,
        archivedAt: Date? = nil, madeBy: String? = nil
    ) throws -> WorkObjectID {
        let parent = try parent ?? place(db, type: type, madeBy: madeBy)
        try db.execute(
            sql: """
                INSERT INTO work_object(\(WorkObjectRow.columns))
                VALUES (?,?,?, COALESCE((SELECT MAX(position) FROM work_object WHERE parent_id IS ?), 0) + 1, ?, ?)
                """, arguments: [id, type, parent, parent, name, archivedAt?.stored])
        return id
    }

    /// The first child of `parent` that is not archived and has this type and this name, compared without case and
    /// without the spaces around it.
    static func liveChild(_ db: Database, type: TypeID, parent: WorkObjectID?, name: String) throws -> WorkObjectID? {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return try Row.fetchAll(
            db,
            sql: """
                SELECT id, name FROM work_object
                WHERE type = ? AND parent_id IS ? AND archived_at IS NULL ORDER BY position, rowid
                """, arguments: [type, parent]
        ).first { ($0["name"] as String).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == wanted }?["id"]
    }

    /// The one folder that is not archived and holds objects of `type`. Nil when none does, and when several do: then
    /// the person chooses.
    static func home(_ db: Database, of type: TypeID) throws -> WorkObjectID? {
        let homes = try String.fetchAll(
            db, sql: "SELECT id FROM work_object WHERE holds = ? AND archived_at IS NULL", arguments: [type])
        return homes.count == 1 ? homes.first : nil
    }

    /// The folder that holds the page of the machine of `task`. Nil when the machine, its page or the folder is gone.
    static func folder(_ db: Database, ofMachine task: String) throws -> WorkObjectID? {
        try String.fetchOne(
            db,
            sql: """
                SELECT folder.id FROM machine_now
                JOIN work_object page ON page.id = machine_now.page_id
                JOIN work_object folder ON folder.id = page.parent_id
                WHERE machine_now.task = ? AND machine_now.state <> 'deleted' AND page.archived_at IS NULL
                    AND folder.archived_at IS NULL
                """, arguments: [task])
    }

    /// Where an object of `type` with no parent goes: the folder of the machine of `madeBy`, else the one folder that
    /// holds the type. Nil: among the roots.
    static func place(_ db: Database, type: TypeID, madeBy: String?) throws -> WorkObjectID? {
        try madeBy.flatMap { try folder(db, ofMachine: $0) } ?? home(db, of: type)
    }

    /// The root folder a template makes: the one of its name that is not archived, made when the store has none. It
    /// takes the type of the objects the template's folder holds, when it holds none yet.
    static func folder(_ db: Database, for start: GalleryTemplate.FolderStart) throws -> WorkObjectID {
        let type = ObjectTypes.folder.id
        let folder =
            try liveChild(db, type: type, parent: nil, name: start.name)
            ?? insert(db, type: type, parent: nil, name: start.name)
        if let holds = start.holds { try setHolds(db, folder: folder, to: holds) }
        return folder
    }

    /// The folder holds objects of `type` from now on, unless it already holds a type.
    static func setHolds(_ db: Database, folder: WorkObjectID, to type: TypeID) throws {
        try db.execute(
            sql: "UPDATE work_object SET holds = ? WHERE id = ? AND holds IS NULL", arguments: [type, folder])
    }

    /// Makes the page of a machine in `folder`, or in the folder its template belongs to, and points the machine at it.
    @discardableResult
    static func addMachinePage(
        _ db: Database, machine: Int64, template: String, name: String, folder: WorkObjectID?
    ) throws -> WorkObjectID {
        let folder = try folder ?? Self.folder(db, for: GalleryTemplate.folder(forMachine: template))
        let page = try insert(db, type: ObjectTypes.machinePage.id, parent: folder, name: name)
        try db.execute(sql: "UPDATE machine SET page_id = ? WHERE id = ?", arguments: [page, machine])
        return page
    }

    /// Each root that has a place, with that place, in the order of the roots.
    static func rootsWithAPlace(_ db: Database) throws -> [(object: WorkObjectID, place: WorkObjectID)] {
        let roots = try String.fetchAll(
            db, sql: "SELECT id FROM work_object WHERE parent_id IS NULL ORDER BY position, rowid")
        return try roots.compactMap { root in
            let events = try db.fetch(
                "work_event", "SELECT id, body FROM work_event WHERE object = ?", [root]
            ) { try $0.json("body", as: WorkEvent.self) }
            guard let summary = EventSummary(events) else { return nil }
            return try place(db, type: summary.type, madeBy: summary.madeBy).map { (root, $0) }
        }
    }

    /// Gives each object its node: a new one goes to its place, with the type and name its events give. An object
    /// that has a node keeps its place and takes the name and archive time its events give. An object whose events
    /// hold no `create` has none.
    static func project(_ db: Database, objects: [WorkObjectID]) throws {
        var seen: Set<WorkObjectID> = []
        for id in objects where seen.insert(id).inserted {
            let events = try db.fetch(
                "work_event", "SELECT id, body FROM work_event WHERE object = ?", [id]
            ) { try $0.json("body", as: WorkEvent.self) }
            guard let summary = EventSummary(events) else { continue }
            try db.execute(
                sql: "UPDATE work_object SET name = ?, archived_at = ? WHERE id = ?",
                arguments: [summary.name, summary.archivedAt?.stored, id])
            if db.changesCount == 0 {
                try insert(
                    db, id: id, type: summary.type, parent: nil, name: summary.name, archivedAt: summary.archivedAt,
                    madeBy: summary.madeBy)
            }
        }
    }
}
