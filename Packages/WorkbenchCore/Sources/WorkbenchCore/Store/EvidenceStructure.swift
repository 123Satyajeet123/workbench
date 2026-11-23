import Foundation
import GRDB
import Lines

extension EvidenceStamp {
    /// A statement that is true when the entity named by the column `key` is live: a note line that has words, or a block
    /// of a machine that is live. A row of structure may name only such an entity. Every write and every clean-up of
    /// structure asks this one question.
    static func liveEntity(_ key: String) -> String {
        """
        (EXISTS (SELECT 1 FROM evidence WHERE evidence.entity_key = \(key) AND evidence.tombstone = 0)
            OR EXISTS (SELECT 1 FROM machine_block WHERE machine_block.entity_key = \(key)
                AND machine_block.state = 'live'))
        """
    }

    /// Writes the structure of one container. A supersession is written once and never changes. The order replaces the
    /// container's old one: the order the structure gives, with each live machine block of the old order that it does
    /// not name kept after the paragraph it followed (`PageOrder`).
    static func write(_ structure: ContainerStructure, of container: String, at now: Int64, in db: Database) throws {
        for supersession in structure.supersessions {
            try db.execute(
                sql: "INSERT OR IGNORE INTO entity_supersede(entity_key, into_key, at) VALUES (?, ?, ?)",
                arguments: [Data(supersession.entity.bytes), Data(supersession.into.bytes), now])
        }
        let named = structure.order.map { Data($0.bytes) }
        try replaceOrder(
            of: container, with: try placingUnnamedMachineBlocks(in: container, among: named, in: db), in: db)
    }

    /// The one write of a container's order. An entity that is not live has no place in it, such as a paragraph the
    /// store refused because its name had ended.
    static func replaceOrder(of container: String, with order: [Data], in db: Database) throws {
        try db.execute(sql: "DELETE FROM container_order WHERE container = ?", arguments: [container])
        for (position, key) in order.enumerated() {
            try db.execute(
                sql: """
                    INSERT INTO container_order(container, position, entity_key)
                    SELECT ?, ?, key FROM (SELECT ? AS key) WHERE \(liveEntity("key"))
                    """, arguments: [container, position, key])
        }
    }

    /// The entities of a container's order now, in order.
    static func order(of container: String, in db: Database) throws -> [Data] {
        try Data.fetchAll(
            db, sql: "SELECT entity_key FROM container_order WHERE container = ? ORDER BY position",
            arguments: [container])
    }

    /// `named` with the live machine blocks of the container's order that `named` does not name placed after the
    /// paragraph each followed. A paragraph that was joined to another is followed through `entity_supersede` to the
    /// one that holds its words.
    private static func placingUnnamedMachineBlocks(in container: String, among named: [Data], in db: Database) throws
        -> [Data]
    {
        let machine = Set(
            try Data.fetchAll(
                db,
                sql: """
                    SELECT entity_key FROM machine_block WHERE state = 'live'
                        AND entity_key IN (SELECT entity_key FROM container_order WHERE container = ?)
                    """, arguments: [container])
        ).subtracting(named)
        guard !machine.isEmpty else { return named }
        let joined = Dictionary(
            uniqueKeysWithValues: try Row.fetchAll(
                db,
                sql: """
                    WITH RECURSIVE chain(entity_key, into_key) AS (
                        SELECT entity_key, into_key FROM entity_supersede
                        WHERE entity_key IN (SELECT entity_key FROM container_order WHERE container = ?)
                        UNION SELECT s.entity_key, s.into_key FROM entity_supersede s
                        JOIN chain ON s.entity_key = chain.into_key)
                    SELECT entity_key, into_key FROM chain
                    """, arguments: [container]
            ).map { ($0["entity_key"] as Data, $0["into_key"] as Data) })
        return PageOrder.merged(
            old: try order(of: container, in: db), notes: named, isMachine: { machine.contains($0) },
            into: { joined[$0] })
    }

    /// Structure goes with the entities it is about: a row of an entity that is no longer live is removed.
    static func dropOrphanStructure(in db: Database) throws {
        try db.execute(sql: "DELETE FROM entity_supersede WHERE NOT \(liveEntity("entity_supersede.entity_key"))")
        try db.execute(sql: "DELETE FROM container_order WHERE NOT \(liveEntity("container_order.entity_key"))")
    }
}
