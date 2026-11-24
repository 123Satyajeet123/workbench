import Foundation
import GRDB

/// How a fact came to stand under a work object. The raw value is what the store keeps.
public enum FilingHow: String, CaseIterable, Sendable {
    /// The code put it in the folder of the machine that found it.
    case machineFolder
    /// The code put it under the work object it was made from, such as the deal of a deal's action.
    case origin
    /// A model proposed the place. It waits for a person.
    case modelProposed
    /// A person agreed with the place.
    case personConfirmed
    /// A person chose another place.
    case personMoved

    /// Whether a person made the filing, so that it records the surface they made it on.
    var isPerson: Bool { self == .personConfirmed || self == .personMoved }
}

/// The one home of a fact: the work object the latest filing names, and how it came there.
public struct Filing: Sendable, Equatable {
    public var object: WorkObject
    public var how: FilingHow
    public var at: Date
}

public enum FilingError: Error, Equatable {
    /// A filing by a person has a surface, and any other filing has none.
    case surface(FilingHow)
    /// A person confirmed or moved a fact that has no home yet.
    case noHome(item: ItemID)
}

extension Store {
    /// Files a fact under a work object. The new row is the fact's home from now on; the earlier rows stay as history.
    public func file(item: ItemID, into object: WorkObjectID, how: FilingHow, surface: MarkSurface? = nil) throws {
        try writer.write { db in try file(db, item: item, into: object, how: how, surface: surface) }
    }

    /// A person agrees with the place a fact waits to be filed under, or else with the home it has.
    public func confirmHome(of item: ItemID, surface: MarkSurface) throws {
        try writer.write { db in
            guard let place = try Queries.proposedHome(db, of: item) ?? Queries.filing(db, of: item)?.object else {
                throw FilingError.noHome(item: item)
            }
            try file(db, item: item, into: place.id, how: .personConfirmed, surface: surface)
        }
    }

    /// A person puts a fact under another work object.
    public func moveHome(of item: ItemID, into object: WorkObjectID, surface: MarkSurface) throws {
        try file(item: item, into: object, how: .personMoved, surface: surface)
    }

    func file(
        _ db: Database, item: ItemID, into object: WorkObjectID, how: FilingHow, surface: MarkSurface?
    ) throws {
        guard how.isPerson == (surface != nil) else { throw FilingError.surface(how) }
        try db.execute(
            sql: "INSERT INTO fact_link(item_id, object_id, how, at, surface) VALUES (?,?,?,?,?)",
            arguments: [item, object, how.rawValue, clock().stored, surface?.rawValue])
    }

    /// Files the fact a model proposed a home for, unless it already stands there or waits for it.
    func fileProposal(_ db: Database, item: ItemID, into object: WorkObjectID) throws {
        let standing = try Queries.proposedHome(db, of: item) ?? Queries.filing(db, of: item)?.object
        guard standing?.id != object else { return }
        try file(db, item: item, into: object, how: .modelProposed, surface: nil)
    }
}

enum FactFiling {
    /// Gives the fact that has no home yet its default home, at the time the fact was made, so every fact has a home
    /// from its first reading: the folder of its machine, else the work object it was made from, which `origin`
    /// names: the field of the fact that holds that object's id. With no `item`, every such fact is filed.
    static func fileInDefaultHomes(_ db: Database, item: ItemID? = nil, origin: HelperSpec.Field? = nil) throws {
        try fileInMachineFolders(db, item: item)
        if let origin { try fileInOrigins(db, item: item, field: origin.name) }
    }

    private static func fileInOrigins(_ db: Database, item: ItemID?, field: String) throws {
        try db.execute(
            sql: """
                INSERT INTO fact_link(item_id, object_id, how, at, surface)
                SELECT item.id, origin.id, ?, item.created_at, NULL
                FROM item JOIN work_object origin ON origin.id = json_extract(item.fields, '$.' || ?)
                WHERE (? IS NULL OR item.id = ?)
                    AND NOT EXISTS (SELECT 1 FROM fact_link WHERE fact_link.item_id = item.id)
                """, arguments: [FilingHow.origin.rawValue, field, item, item])
    }

    private static func fileInMachineFolders(_ db: Database, item: ItemID?) throws {
        try db.execute(
            sql: """
                INSERT INTO fact_link(item_id, object_id, how, at, surface)
                SELECT item.id, page.parent_id, ?, item.created_at, NULL
                FROM item JOIN machine ON machine.task = item.task JOIN work_object page ON page.id = machine.page_id
                WHERE page.parent_id IS NOT NULL AND (? IS NULL OR item.id = ?)
                    AND NOT EXISTS (SELECT 1 FROM fact_link WHERE fact_link.item_id = item.id)
                """, arguments: [FilingHow.machineFolder.rawValue, item, item])
    }
}

extension Queries {
    /// The home of a fact: the work object of its latest filing. Nil when it has none.
    public func home(of item: ItemID) throws -> WorkObject? { try filing(of: item)?.object }

    /// The home of a fact and how it came there.
    public func filing(of item: ItemID) throws -> Filing? {
        try reader.read { db in try Self.filing(db, of: item) }
    }

    static func filing(_ db: Database, of item: ItemID) throws -> Filing? {
        guard
            let row = try Row.fetchOne(
                db, sql: "SELECT object_id, how, at FROM fact_home WHERE item_id = ?", arguments: [item]),
            let object = try Self.workObjects(db, where: "id = ?", [row["object_id"] as String]).first
        else { return nil }
        return Filing(object: object, how: try row.enumeration("how"), at: try row.date("at"))
    }

    /// The place a model proposed for a fact that no person has acted on: its latest proposal, when that is newer than
    /// the home. Nil otherwise. A fact's home line asks "Filed to X?" for it.
    public func proposedHome(of item: ItemID) throws -> WorkObject? {
        try reader.read { db in try Self.proposedHome(db, of: item) }
    }

    static func proposedHome(_ db: Database, of item: ItemID) throws -> WorkObject? {
        guard
            let id = try String.fetchOne(
                db,
                sql: """
                    SELECT proposal.object_id FROM fact_link proposal
                    WHERE proposal.item_id = ?1 AND proposal.how = 'modelProposed'
                        AND NOT EXISTS (
                            SELECT 1 FROM fact_home home WHERE home.item_id = ?1
                                AND (home.at, home.id) > (proposal.at, proposal.id))
                    ORDER BY proposal.at DESC, proposal.id DESC LIMIT 1
                    """, arguments: [item])
        else { return nil }
        return try Self.workObjects(db, where: "id = ?", [id]).first
    }

    /// The facts whose home is `object`, and with `includeChildren` the facts whose home is any object below it.
    public func facts(in object: WorkObjectID, includeChildren: Bool) throws -> [Item] {
        try reader.read { db in try Self.facts(in: object, includeChildren: includeChildren, db) }
    }

    static func facts(in object: WorkObjectID, includeChildren: Bool, _ db: Database) throws -> [Item] {
        try db.fetch(
            "item",
            """
            WITH RECURSIVE subtree(id) AS (
                SELECT ? UNION ALL SELECT child.id FROM work_object child JOIN subtree ON child.parent_id = subtree.id
                WHERE ?)
            SELECT \(Self.itemColumns) FROM \(Self.itemRows)
            WHERE id IN (SELECT item_id FROM fact_home WHERE object_id IN (SELECT id FROM subtree))
            ORDER BY day DESC, start_at DESC, id
            """, [object, includeChildren ? 1 : 0], as: Item.init(row:))
    }
}
