import Foundation
import GRDB

extension Store {
    /// The work object, as the reader sees it: its type, name and stage, the objects below it that are not archived,
    /// and the facts filed in it that pass the audience check, newest first. An archived object opens only by its own
    /// id. Each line a returned fact cites goes into the window of the run.
    public func openObject(_ id: WorkObjectID, factLimit: Int = 50, in context: ToolContext) throws -> FoundObject? {
        let audience = try ReaderAudience(reader: context.reader)
        let viewer = context.reader.rawValue
        return try writer.write { db in
            guard let object = try Queries.workObjects(db, where: "id = ?", [id], viewer: viewer).first else {
                return nil
            }
            let children = try Queries.workObjects(
                db, where: "parent_id = ? AND archived_at IS NULL", [id], viewer: viewer)
            var filed = try Queries.facts(in: id, includeChildren: false, db).makeIterator()
            let facts = try Self.admitted(next: { filed.next() }, limit: factLimit, audience: audience, in: db)
            let numbers = try Self.trace(facts.flatMap(\.cites), in: context.run, db)
            return FoundObject(
                id: object.id, type: object.type.id, name: object.name,
                stages: object.stages.compactMap { stage in object.type.stages.first { $0.id == stage }?.label },
                archived: object.archived,
                children: children.map { FoundObject.Child(id: $0.id, type: $0.type.id, name: $0.name) },
                facts: try facts.map { try $0.found(numbers: numbers) })
        }
    }
}
