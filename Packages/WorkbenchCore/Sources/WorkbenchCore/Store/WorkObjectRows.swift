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
    /// Adds a node as the last child of `parent`.
    @discardableResult
    static func insert(
        _ db: Database, id: WorkObjectID = UUID().uuidString, type: TypeID, parent: WorkObjectID?, name: String,
        archivedAt: Date? = nil
    ) throws -> WorkObjectID {
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

    /// The root folder of this name that is not archived, made when the store has none.
    static func folder(_ db: Database, named name: String) throws -> WorkObjectID {
        let type = ObjectTypes.folder.id
        return try liveChild(db, type: type, parent: nil, name: name)
            ?? insert(db, type: type, parent: nil, name: name)
    }

    /// Makes the page of a machine in `folder`, or in the folder its template belongs to, and points the machine at it.
    @discardableResult
    static func addMachinePage(
        _ db: Database, machine: Int64, template: String, name: String, folder: WorkObjectID?
    ) throws -> WorkObjectID {
        let folder = try folder ?? Self.folder(db, named: TeamTemplate.folderName(forMachine: template))
        let page = try insert(db, type: ObjectTypes.machinePage.id, parent: folder, name: name)
        try db.execute(sql: "UPDATE machine SET page_id = ? WHERE id = ?", arguments: [page, machine])
        return page
    }

    /// Gives each object its node: a new one is the last root, with the type and name its events give. An object that
    /// has a node keeps its place and takes the name and archive time its events give. An object whose events hold no
    /// `create` has none.
    static func project(_ db: Database, objects: [WorkObjectID]) throws {
        var seen: Set<WorkObjectID> = []
        for id in objects where seen.insert(id).inserted {
            let events = try db.fetch(
                "work_event", "SELECT id, body FROM work_event WHERE object = ?", [id]
            ) { try $0.json("body", as: WorkEvent.self) }
            guard let summary = EventSummary(events) else { continue }
            try db.execute(
                sql: """
                    INSERT INTO work_object(\(WorkObjectRow.columns))
                    VALUES (?,?,NULL, COALESCE((SELECT MAX(position) FROM work_object WHERE parent_id IS NULL), 0) + 1, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET name = excluded.name, archived_at = excluded.archived_at
                    """, arguments: [id, summary.type, summary.name, summary.archivedAt?.stored])
        }
    }
}
