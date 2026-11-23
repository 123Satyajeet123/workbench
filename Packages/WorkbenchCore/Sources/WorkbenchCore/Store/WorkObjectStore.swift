import Foundation
import GRDB

public enum WorkObjectError: Error, Equatable {
    case unknown(WorkObjectID)
    case noName
    /// A node may not move under itself or under a node below it.
    case cycle(WorkObjectID)
    /// The events of a shared object keep its name and its archive time, so a person changes them as events.
    case keptByEvents(WorkObjectID)
}

extension Store {
    /// The work object of this type under `parent` with this name, or a new one as the last child of `parent` (the last
    /// root with no parent). Names match without case and without the spaces around them, and an archived object does
    /// not match, so making the same folder twice gives one folder. A folder has the type `ObjectTypes.folder`, a page
    /// `ObjectTypes.page`.
    @discardableResult
    public func createWorkObject(type: ObjectType, parent: WorkObjectID?, name: String) throws -> WorkObject {
        guard let name = name.cleaned else { throw WorkObjectError.noName }
        return try writer.write { db in
            if let parent { try Queries.require(db, parent) }
            let id =
                try WorkObjectRows.liveChild(db, type: type.id, parent: parent, name: name)
                ?? WorkObjectRows.insert(db, type: type.id, parent: parent, name: name)
            return try Queries.workObjects(db, where: "id = ?", [id])[0]
        }
    }

    /// An archived object leaves the tree. Its facts, notes and machines stay where they are.
    public func archive(_ id: WorkObjectID) throws {
        try writer.write { db in
            try Queries.requireNotKeptByEvents(db, id)
            try db.execute(sql: "UPDATE work_object SET archived_at = ? WHERE id = ?", arguments: [clock().stored, id])
        }
    }

    /// Puts an object last under `parent`, or last among the roots.
    public func move(_ id: WorkObjectID, under parent: WorkObjectID?) throws {
        try writer.write { db in
            try Queries.require(db, id)
            if let parent {
                try Queries.require(db, parent)
                guard try !Queries.isSelfOrDescendant(db, parent, of: id) else { throw WorkObjectError.cycle(id) }
            }
            try db.execute(
                sql: """
                    UPDATE work_object SET parent_id = ?,
                        position = COALESCE((SELECT MAX(position) FROM work_object WHERE parent_id IS ?), 0) + 1
                    WHERE id = ?
                    """, arguments: [parent, parent, id])
        }
    }
}

extension Queries {
    /// The children of `parent`, or the roots when it is nil, in their order. An archived one is left out unless asked
    /// for.
    public func workObjects(parent: WorkObjectID?, includeArchived: Bool) throws -> [WorkObject] {
        try reader.read { db in
            try Self.workObjects(
                db, where: "parent_id IS ? AND (? OR archived_at IS NULL)", [parent, includeArchived ? 1 : 0])
        }
    }

    /// The machines whose page is a child of `object`: the machines that live in that folder.
    public func machines(in object: WorkObjectID) throws -> [Machine] {
        try reader.read { db in
            try db.fetch(
                "machine_now",
                """
                SELECT machine_now.id, machine_now.name, machine_now.template, machine_now.spec, machine_now.state,
                    machine_now.page_id
                FROM machine_now JOIN work_object page ON page.id = machine_now.page_id
                WHERE page.parent_id = ? AND page.archived_at IS NULL AND machine_now.state <> 'deleted'
                ORDER BY page.position, machine_now.id
                """, [object], as: Machine.init(row:))
        }
    }

    /// The objects a model may be shown as places to file a fact under: every kind that holds facts, not archived, in
    /// the order of the tree, the first `limit`.
    public func placesToFile(limit: Int = 40) throws -> [WorkObject] {
        let kinds = ObjectTypes.homes.map(\.id)
        return try reader.read { db in
            try Self.workObjects(
                db, where: "archived_at IS NULL AND type IN (SELECT value FROM json_each(?))",
                [try Coding.json(kinds)], order: "parent_id IS NOT NULL, position, rowid LIMIT \(limit)")
        }
    }

    /// The objects the condition selects, each with the events of its own, in `order`.
    static func workObjects(
        _ db: Database, where condition: String, _ arguments: StatementArguments,
        order: String = "position, rowid"
    ) throws -> [WorkObject] {
        let rows = try db.fetch(
            "work_object", "SELECT \(WorkObjectRow.columns) FROM work_object WHERE \(condition) ORDER BY \(order)",
            arguments, as: WorkObjectRow.init(row:))
        let events = try db.fetch(
            "work_event",
            "SELECT id, body FROM work_event WHERE object IN (SELECT value FROM json_each(?)) ORDER BY clock, id",
            [try Coding.json(rows.map(\.id))]
        ) { try $0.json("body", as: WorkEvent.self) }
        let byObject = Dictionary(grouping: events, by: \.object)
        return rows.map { WorkObject($0, events: byObject[$0.id] ?? [], viewer: "") }
    }

    static func require(_ db: Database, _ id: WorkObjectID) throws {
        guard try Int.fetchOne(db, sql: "SELECT 1 FROM work_object WHERE id = ?", arguments: [id]) != nil else {
            throw WorkObjectError.unknown(id)
        }
    }

    static func requireNotKeptByEvents(_ db: Database, _ id: WorkObjectID) throws {
        try require(db, id)
        guard try Int.fetchOne(db, sql: "SELECT 1 FROM work_event WHERE object = ? LIMIT 1", arguments: [id]) == nil
        else { throw WorkObjectError.keptByEvents(id) }
    }

    /// Whether `node` is `ancestor` or stands below it.
    static func isSelfOrDescendant(_ db: Database, _ node: WorkObjectID, of ancestor: WorkObjectID) throws -> Bool {
        try Int.fetchOne(
            db,
            sql: """
                WITH RECURSIVE subtree(id) AS (
                    SELECT ? UNION ALL SELECT child.id FROM work_object child JOIN subtree ON child.parent_id = subtree.id)
                SELECT 1 FROM subtree WHERE id = ?
                """, arguments: [ancestor, node]) != nil
    }
}
