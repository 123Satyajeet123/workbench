import Foundation
import Lines
import WorkbenchCore

/// The reader as an evidence source (research 56 §1 WhatsApp reader row, research E-R3). One read of a chat gives the
/// lines of every message of a type that has words, a tombstone for each message deleted for everyone, and the cursor
/// that says where the next read starts. The reader asks the policy first, copies the store with the backup API (a
/// read-only open of the other app's file), and checks the file header and the store's identity before it reads.
extension WhatsAppChatReader: EvidenceSource {
    public static let readerVersion = "whatsapp-store 1"
    /// The owner is a member of every audience (research E-R3 §6), and the `actor` of the owner's own lines.
    public static let audienceOwner = "me"

    public var descriptor: SourceDescriptor { .whatsAppChat }

    public func observe(state: @Sendable (String) throws -> ScanState, now: Date) async throws -> SourceRead {
        var read = SourceRead()
        var grants: [String: CaptureGrant] = [:]
        for chat in chatJIDs {
            do {
                grants[chat] = try await policy.grant(for: .whatsapp, label: chat, at: now)
            } catch {
                read.failures.append(LabelFailure(label: chat, error: error))
            }
        }
        guard !grants.isEmpty else { return read }
        let snapshot = try Self.evidenceSnapshot(container)
        let storeID = try Self.storeID(snapshot)
        for chat in chatJIDs {
            guard let grant = grants[chat] else { continue }
            do {
                let plan = Scan.plan(
                    state: try state(chat), storeID: storeID, now: now, window: descriptor.editWindow)
                if let reading = try observe(
                    chat, grant: grant, in: snapshot, storeID: storeID, plan: plan, now: now)
                {
                    read.readings.append(reading)
                }
            } catch {
                read.failures.append(LabelFailure(label: chat, error: error))
            }
        }
        return read
    }

    private static func evidenceSnapshot(_ container: URL) throws -> SQLiteSnapshot {
        let snapshot = try Self.snapshot(container)
        try snapshot.requireColumns(["ZSTANZAID"], in: "ZWAMESSAGE")
        try snapshot.requireColumns(["ZMETADATA"], in: "ZWAMEDIAITEM")
        try snapshot.requireColumns(["Z_UUID"], in: "Z_METADATA")
        return snapshot
    }

    /// The identity of the store: a new one means every row number means another row.
    private static func storeID(_ snapshot: SQLiteSnapshot) throws -> String {
        guard let id = try snapshot.rows("SELECT Z_UUID FROM Z_METADATA").first?.text(0), !id.isEmpty else {
            throw ReadError.unsupportedSchema
        }
        return id
    }

    private func observe(
        _ chat: String, grant: CaptureGrant, in snapshot: SQLiteSnapshot, storeID: String, plan: ScanPlan, now: Date
    ) throws -> SourceReading? {
        guard
            let session = try snapshot.rows(
                "SELECT Z_PK, ZSESSIONTYPE FROM ZWACHATSESSION WHERE ZCONTACTJID = ? AND ZSESSIONTYPE IN (?, ?)",
                binding: [
                    .text(chat), .integer(Int64(SessionType.person)), .integer(Int64(SessionType.group)),
                ]
            ).first
        else { return nil }
        let place = ChatPlace(
            jid: WhatsAppJID.canonical(chat), session: session.integer(0),
            isGroup: Int(session.integer(1)) == SessionType.group)
        let audience = try audience(of: place, in: snapshot)
        let rows = try snapshot.rows(
            """
            SELECT \(MessageIdentity.columns), m.ZMESSAGEDATE, m.ZMESSAGETYPE, m.ZTEXT, i.ZTITLE, i.ZMETADATA,
                i.ZMEDIALOCALPATH
            \(MessageIdentity.tables)
            WHERE m.ZCHATSESSION = ?
                AND (m.Z_PK > ? OR m.ZMESSAGEDATE >= ? OR m.ZMESSAGETYPE = ?)
            ORDER BY m.Z_PK
            """,
            binding: [
                .integer(place.session), .integer(plan.after),
                .real(plan.rescanSince.timeIntervalSinceReferenceDate),
                .integer(Int64(WhatsAppMessageType.revokedCode)),
            ])
        let messages = rows.map(Message.init(row:)).map { readingPhoto($0, now: now) }
        let replies = try identities(
            ofStanzas: Set(messages.compactMap(\.quotedStanza)), in: place, snapshot: snapshot)
        var lines: [ObservedLine] = []
        var census: [Int: TypeCensus] = [:]
        var unkeyed = 0
        for message in messages {
            census[message.typeCode, default: TypeCensus()].count(hasText: message.hasText)
            let treatment = message.type.treatment(hasText: message.hasText)
            guard treatment != .skipped else { continue }
            guard let line = observedLine(message, treatment, in: place, replies: replies, plan: plan) else {
                unkeyed += 1
                continue
            }
            lines.append(line)
        }
        return SourceReading(
            grant: grant, label: chat, container: place.jid, audience: audience, lines: lines,
            cursorAfter: Scan.cursor(
                after: plan, storeID: storeID, highestRow: messages.map(\.identity.row).max(), readAt: now),
            mapsLegacyRefs: plan.mapsLegacyRefs, readerVersion: Self.readerVersion, census: census, unkeyed: unkeyed)
    }

    /// A photo's words are the text in it, read on this Mac, then its caption. Teams post screenshots of builds and
    /// logs as updates. Only a photo sent within the retention (how far back anything reads) is read, so the first reading of a long chat does not
    /// recognize every photo it ever held.
    private func readingPhoto(_ message: Message, now: Date) -> Message {
        guard message.type == .image, let time = message.time, Double(UTCInstant(now).milliseconds - time.milliseconds) / 1000 < CapturePolicy.retention,
            let file = mediaFile(atRelativePath: message.mediaPath)
        else { return message }
        let seen = ImageText.text(in: file)
        guard !seen.isEmpty else { return message }
        var read = message
        read.words = ["[photo] \(seen)", message.words].filter { !$0.isEmpty }
            .joined(separator: WhatsAppMessageText.separator)
        return read
    }

    /// A path counts only when the file exists inside the container's `Message` folder.
    private func mediaFile(atRelativePath path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        let root = container.appending(path: "Message").resolvingSymlinksInPath()
        let file = root.appending(path: path).resolvingSymlinksInPath()
        guard file.path.hasPrefix(root.path + "/"), FileManager.default.fileExists(atPath: file.path) else {
            return nil
        }
        return file
    }

    private func observedLine(
        _ message: Message, _ treatment: WhatsAppMessageType.Treatment, in place: ChatPlace,
        replies: [String: MessageIdentity], plan: ScanPlan
    ) -> ObservedLine? {
        guard let key = message.identity.entityKey(in: place) else { return nil }
        let tombstone = treatment == .tombstone
        let replyTo = message.quotedStanza.flatMap { replies[$0] }.flatMap { $0.entityKey(in: place) }
        return ObservedLine(
            line: tombstone
                ? .tombstone(entity: key, readerVersion: Self.readerVersion)
                : Line(entity: key, text: message.words, readerVersion: Self.readerVersion),
            quality: message.identity.copies > 1 ? .derived : .stable, eventTime: message.time,
            actor: message.identity.actor(in: place), replyTo: tombstone ? nil : replyTo,
            messageRef: message.identity.stanza,
            legacy: plan.mapsLegacyRefs ? LegacyRef(space: .whatsAppRow, ref: message.identity.row) : nil)
    }

    /// Everyone who could read the chat now: the active members of a group, or the other person of a direct chat,
    /// and the owner. A group with no active member fails closed.
    private func audience(of place: ChatPlace, in snapshot: SQLiteSnapshot) throws -> AudienceDigest {
        let members =
            place.isGroup
            ? try snapshot.rows(
                "SELECT ZMEMBERJID FROM ZWAGROUPMEMBER WHERE ZCHATSESSION = ? AND ZISACTIVE = 1 AND ZMEMBERJID <> ''",
                binding: [.integer(place.session)]
            ).compactMap { $0.text(0) } : [place.jid]
        guard !members.isEmpty else { throw ReadError.audienceUnknown }
        return AudienceDigest(owner: Self.audienceOwner, members: members.map(WhatsAppJID.canonical))
    }

    /// The identity of the message each stanza id names in this chat; the lowest row number when a stanza id repeats.
    private func identities(ofStanzas stanzas: Set<String>, in place: ChatPlace, snapshot: SQLiteSnapshot) throws
        -> [String: MessageIdentity]
    {
        var found: [String: MessageIdentity] = [:]
        for batch in Array(stanzas).chunked(by: 500) {
            let marks = Array(repeating: "?", count: batch.count).joined(separator: ",")
            let rows = try snapshot.rows(
                """
                SELECT \(MessageIdentity.columns) \(MessageIdentity.tables)
                WHERE m.ZCHATSESSION = ? AND m.ZSTANZAID IN (\(marks)) ORDER BY m.Z_PK
                """, binding: [.integer(place.session)] + batch.map { .text($0) })
            for identity in rows.map(MessageIdentity.init(row:)) {
                if let stanza = identity.stanza, found[stanza] == nil { found[stanza] = identity }
            }
        }
        return found
    }
}

/// The chat being read: its canonical jid, its row in the store, and whether it is a group.
struct ChatPlace {
    var jid: String
    var session: Int64
    var isGroup: Bool
}

/// What names a message in a chat: its row, who sent it, its stanza id, and its place among rows with the same name.
struct MessageIdentity {
    /// The columns `init(row:)` reads, then the tables they come from.
    static let columns = """
        m.Z_PK, m.ZISFROMME, m.ZSTANZAID, g.ZMEMBERJID,
        (SELECT count(*) FROM ZWAMESSAGE d WHERE d.ZCHATSESSION = m.ZCHATSESSION AND d.ZSTANZAID = m.ZSTANZAID
            AND d.ZISFROMME = m.ZISFROMME AND d.ZGROUPMEMBER IS m.ZGROUPMEMBER AND d.Z_PK < m.Z_PK),
        (SELECT count(*) FROM ZWAMESSAGE d WHERE d.ZCHATSESSION = m.ZCHATSESSION AND d.ZSTANZAID = m.ZSTANZAID
            AND d.ZISFROMME = m.ZISFROMME AND d.ZGROUPMEMBER IS m.ZGROUPMEMBER)
        """
    static let tables = """
        FROM ZWAMESSAGE m
        LEFT JOIN ZWAMEDIAITEM i ON i.ZMESSAGE = m.Z_PK
        LEFT JOIN ZWAGROUPMEMBER g ON g.Z_PK = m.ZGROUPMEMBER
        """

    var row: Int64
    var fromMe: Bool
    var stanza: String?
    var member: String?
    /// How many rows with the same chat, author and stanza id come before this one, by row number.
    var occurrence: UInt32
    /// How many rows have that name, this one included. More than one makes the lines `derived`.
    var copies: Int

    init(row: SQLiteRow) {
        self.row = row.integer(0)
        fromMe = row.integer(1) != 0
        stanza = row.text(2)
        member = row.text(3)
        occurrence = UInt32(clamping: row.integer(4))
        copies = Int(row.integer(5))
    }

    /// The jid or `me` that sent the message; nil in a group when the sender is unknown.
    func actor(in place: ChatPlace) -> String? {
        if fromMe { return WhatsAppChatReader.audienceOwner }
        return place.isGroup ? member.map(WhatsAppJID.canonical) : place.jid
    }

    func entityKey(in place: ChatPlace) -> EntityKey? {
        guard let stanza, !stanza.isEmpty else { return nil }
        if !place.isGroup {
            return try? EntityKey.whatsAppDirect(
                chat: place.jid, fromMe: fromMe, stanzaID: stanza, occurrence: occurrence)
        }
        guard let author = fromMe ? GroupAuthor.me : member.map(GroupAuthor.member) else { return nil }
        return try? EntityKey.whatsAppGroup(chat: place.jid, author: author, stanzaID: stanza, occurrence: occurrence)
    }
}

/// One row of the read: its identity, its type, its words, and the stanza id it quotes.
private struct Message {
    var identity: MessageIdentity
    var typeCode: Int
    var time: UTCInstant?
    var words: String
    var quotedStanza: String?
    var mediaPath: String?

    var type: WhatsAppMessageType { WhatsAppMessageType(code: typeCode) }
    var hasText: Bool { !words.isEmpty }

    init(row: SQLiteRow) {
        identity = MessageIdentity(row: row)
        time = row.isNull(6) ? nil : UTCInstant(Date(timeIntervalSinceReferenceDate: row.real(6)))
        typeCode = Int(row.integer(7))
        words = WhatsAppMessageText.compose(title: row.text(9), text: row.text(8))
        quotedStanza = row.blob(10).flatMap { WhatsAppReply.quotedStanzaID(metadata: $0) }
        mediaPath = row.text(11)
    }
}

extension TypeCensus {
    fileprivate mutating func count(hasText: Bool) {
        rows += 1
        if hasText { rowsWithText += 1 }
    }
}

extension Array {
    fileprivate func chunked(by size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
