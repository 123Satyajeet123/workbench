import Foundation
import GRDB
import Lines

extension EvidenceStamp {
    /// Writes the structure of one container. A supersession is written once and never changes. The order replaces the
    /// container's old one. An entity with no text line has no place in it, such as one the store refused because its
    /// name had ended.
    static func write(_ structure: ContainerStructure, of container: String, at now: Int64, in db: Database) throws {
        for supersession in structure.supersessions {
            try db.execute(
                sql: "INSERT OR IGNORE INTO entity_supersede(entity_key, into_key, at) VALUES (?, ?, ?)",
                arguments: [Data(supersession.entity.bytes), Data(supersession.into.bytes), now])
        }
        try db.execute(sql: "DELETE FROM container_order WHERE container = ?", arguments: [container])
        for (position, entity) in structure.order.enumerated() {
            try db.execute(
                sql: """
                    INSERT INTO container_order(container, position, entity_key) SELECT ?, ?, ?
                    WHERE EXISTS (SELECT 1 FROM evidence WHERE entity_key = ? AND tombstone = 0)
                    """,
                arguments: [container, position, Data(entity.bytes), Data(entity.bytes)])
        }
    }

    /// Structure goes with the lines it is about: a row of an entity that has no text line left is removed.
    static func dropOrphanStructure(in db: Database) throws {
        let hasText = "EXISTS (SELECT 1 FROM evidence WHERE evidence.entity_key = %@.entity_key AND tombstone = 0)"
        try db.execute(
            sql: "DELETE FROM entity_supersede WHERE NOT "
                + hasText.replacingOccurrences(of: "%@", with: "entity_supersede"))
        try db.execute(
            sql: "DELETE FROM container_order WHERE NOT "
                + hasText.replacingOccurrences(of: "%@", with: "container_order"))
    }
}
