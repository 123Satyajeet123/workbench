import Foundation
import Lines
import WorkbenchCore

/// The reader as a container source: every chat and group the Mac's WhatsApp store holds, and the active members of
/// each group. It gives ids and names, never a message, and only while capture and the WhatsApp switch are on.
extension WhatsAppChatReader {
    public func sightings(policy: CapturePolicy, now: Date) throws -> [ContainerSighting] {
        guard policy.mode != .off else { throw ReadError.denied(.captureOff) }
        guard policy.isEnabled(descriptor.consent) else { throw ReadError.denied(.sourceSwitchedOff) }
        return try store.read { database in try sightings(in: database, now: now) }
    }

    private func sightings(in database: ReadOnlyDatabase, now: Date) throws -> [ContainerSighting] {
        let members = try Self.activeMembers(in: database)
        return try database.rows(
            """
            SELECT ZCONTACTJID, ZPARTNERNAME, ZSESSIONTYPE FROM ZWACHATSESSION
            WHERE ZCONTACTJID IS NOT NULL AND (ZSESSIONTYPE = ? OR (ZSESSIONTYPE = ? AND ZPARTNERNAME IS NOT NULL))
            ORDER BY ZLASTMESSAGEDATE DESC
            """, binding: [.integer(Int64(SessionType.person)), .integer(Int64(SessionType.group))]
        ).compactMap { row in
            guard let jid = row.text(0) else { return nil }
            let isGroup = row.integer(2) == Int64(SessionType.group)
            return ContainerSighting(
                container: Container(
                    id: WhatsAppJID.canonical(jid), kind: isGroup ? .group : .direct, title: row.text(1) ?? jid),
                source: descriptor.key, observedAt: now,
                membership: isGroup ? Membership(members: members[jid] ?? [], proof: .sourceTable) : nil)
        }
    }

    /// The active members of every group, by the group's id: ids only.
    private static func activeMembers(in database: ReadOnlyDatabase) throws -> [String: [String]] {
        var byGroup: [String: [String]] = [:]
        let rows = try database.rows(
            """
            SELECT s.ZCONTACTJID, g.ZMEMBERJID FROM ZWAGROUPMEMBER g
            JOIN ZWACHATSESSION s ON s.Z_PK = g.ZCHATSESSION
            WHERE s.ZSESSIONTYPE = ? AND g.ZISACTIVE = 1 AND g.ZMEMBERJID <> ''
            """, binding: [.integer(Int64(SessionType.group))])
        for row in rows {
            guard let group = row.text(0), let member = row.text(1) else { continue }
            byGroup[group, default: []].append(WhatsAppJID.canonical(member))
        }
        return byGroup
    }
}
