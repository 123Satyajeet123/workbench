import Foundation
import GRDB
import Kernel
import Lines

/// A row of the old `mail_part` table: mail the person opened before mail lines were evidence lines. It holds no
/// recipients and no account address, and its sender is the text the old reader kept.
struct OldMailPart: Equatable {
    var id: Int64
    var threadID: String
    var messageID: String
    var file: String
    var page: Int
    var label: String
    var sender: String
    var sentAt: Date
    var text: String

    var isDeck: Bool { page > 0 }
}

/// What a move of the old mail rows into the evidence store would do, or did. Counts only.
public struct MailBackfillCounts: Sendable, Equatable {
    /// Rows in `mail_part`.
    public var parts = 0
    /// Rows that become evidence lines: of those, messages and deck pages.
    public var written = 0
    public var messages = 0
    public var deckPages = 0
    /// Written rows whose sender is known (group member) and whose sender is not (unknown authority).
    public var senderKnown = 0
    public var senderUnknown = 0
    /// Refused: the person's mail consent does not name the row's label now.
    public var refusedLabelNotAllowed = 0
    /// Refused: the row has no thread or message id to name a line by.
    public var refusedNoKey = 0
}

/// The one-time move of old mail rows into the evidence store. SQL cannot make a line id (no SHA-256 in a schema
/// step), so the move is code that runs once at start and writes through the one writer.
///
/// An old row has no recipients, so its audience is the narrowest the row proves: the owner and the sender it names.
/// A smaller audience refuses more shares, never fewer. Its authority is `group_member` when the sender is known and
/// `unknown` when not; the account address is not known, so no old row is the person's own words.
enum MailBackfill {
    struct Move {
        var label: String
        var thread: String
        var audience: AudienceDigest
        var lines: [ObservedLine]
        var partIDs: [Int64]
    }

    /// The address in a stored sender, which the old reader kept as `Name <address>` or `address`; nil when it has none.
    static func address(ofSender sender: String) -> String? {
        let text = sender.trimmingCharacters(in: .whitespacesAndNewlines)
        let inBrackets = text.lastIndex(of: "<").flatMap { open in
            text.lastIndex(of: ">").flatMap { close in
                open < close ? String(text[text.index(after: open)..<close]) : nil
            }
        }
        let candidate = inBrackets ?? text
        let address = MailPeople.canonical(candidate)
        return address.contains("@") && !address.contains(where: \.isWhitespace) ? address : nil
    }

    private static func key(of part: OldMailPart) -> EntityKey? {
        part.isDeck
            ? try? MailLineKey.deckPage(
                thread: part.threadID, message: part.messageID, file: part.file, page: part.page)
            : try? MailLineKey.message(thread: part.threadID, message: part.messageID)
    }

    private static func line(of part: OldMailPart, key: EntityKey, actor: String?) -> ObservedLine? {
        let place = part.isDeck ? try? Coding.json(FilePlace(file: part.file, page: part.page)) : nil
        return ObservedLine(
            line: Line(entity: key, text: part.text, readerVersion: MailReader.version),
            eventTime: UTCInstant(part.sentAt), actor: actor, messageRef: part.messageID,
            legacy: LegacyRef(space: .mailPart, ref: part.id), coordinate: place)
    }

    /// What a move of `parts` does under a consent that allows `labels`. Pure.
    static func counts(of parts: [OldMailPart], allowed labels: Set<String>) -> MailBackfillCounts {
        var counts = MailBackfillCounts()
        counts.parts = parts.count
        for part in parts {
            guard labels.contains(part.label) else {
                counts.refusedLabelNotAllowed += 1
                continue
            }
            guard key(of: part) != nil else {
                counts.refusedNoKey += 1
                continue
            }
            counts.written += 1
            if part.isDeck { counts.deckPages += 1 } else { counts.messages += 1 }
            if address(ofSender: part.sender) == nil { counts.senderUnknown += 1 } else { counts.senderKnown += 1 }
        }
        return counts
    }

    /// The writes a move makes: for each label, thread and sender, the lines of the rows the consent allows.
    static func moves(of parts: [OldMailPart], allowed labels: Set<String>) -> [Move] {
        struct Group: Hashable {
            var label: String
            var thread: String
            var sender: String?
        }
        var order: [Group] = []
        var grouped: [Group: Move] = [:]
        for part in parts where labels.contains(part.label) {
            let sender = address(ofSender: part.sender)
            guard let key = key(of: part), let line = line(of: part, key: key, actor: sender) else { continue }
            let group = Group(label: part.label, thread: part.threadID, sender: sender)
            if grouped[group] == nil {
                order.append(group)
                grouped[group] = Move(
                    label: part.label, thread: part.threadID,
                    audience: AudienceDigest(owner: WhatsAppAudience.owner, members: [sender].compactMap { $0 }),
                    lines: [], partIDs: [])
            }
            grouped[group]?.lines.append(line)
            grouped[group]?.partIDs.append(part.id)
        }
        return order.compactMap { grouped[$0] }
    }
}

extension Store {
    private func oldMailParts() throws -> [OldMailPart] {
        try writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, thread_id, message_id, name, page, label, sender, sent_at, text FROM mail_part ORDER BY id
                    """
            ).map {
                OldMailPart(
                    id: $0["id"], threadID: $0["thread_id"], messageID: $0["message_id"], file: $0["name"],
                    page: $0["page"], label: $0["label"], sender: $0["sender"], sentAt: try $0.date("sent_at"),
                    text: $0["text"])
            }
        }
    }

    private func allowedMailLabels() throws -> Set<String> {
        let policy = try currentPolicy()
        let now = clock()
        return Set(
            (policy.allowList[.mail] ?? []).filter {
                policy.authorize(CaptureRequest(kind: .mail, label: $0), at: now).grant != nil
            })
    }

    /// What `moveMailPartsToEvidence` would write and refuse now. Changes nothing, reads no text out of the store.
    public func previewMailBackfill() throws -> MailBackfillCounts {
        MailBackfill.counts(of: try oldMailParts(), allowed: try allowedMailLabels())
    }

    /// Writes the old mail rows the consent allows as evidence lines through the one writer, maps their old citation
    /// ids (`mail_part`), then deletes the rows it moved. A row it refuses stays where it is until the retention or a
    /// delete of the mail kind removes it. Safe to run again: a line already stored is only seen again.
    @discardableResult
    public func moveMailPartsToEvidence(owner: PersonID) throws -> MailBackfillCounts {
        let parts = try oldMailParts()
        let labels = try allowedMailLabels()
        var moved: [Int64] = []
        for move in MailBackfill.moves(of: parts, allowed: labels) {
            guard
                let grant = try currentPolicy().authorize(CaptureRequest(kind: .mail, label: move.label), at: clock())
                    .grant
            else { continue }
            let reading = SourceReading(
                grant: grant, label: move.label, container: move.thread, audience: move.audience, lines: move.lines,
                cursorAfter: nil, readerVersion: MailReader.version)
            _ = try record(reading, of: .gmailMail, owner: owner)
            moved += move.partIDs
        }
        try writer.write { db in
            try db.execute(
                sql: "DELETE FROM mail_part WHERE id IN (SELECT value FROM json_each(?))",
                arguments: [try Coding.json(moved)])
        }
        if !moved.isEmpty { try finishErase(removedRows: true) }
        return MailBackfill.counts(of: parts, allowed: labels)
    }
}

extension MailBackfillCounts {
    /// What the move of old mail rows would write and refuse on a copy of the store in `directory`. Counts only.
    public static func preview(onCopyOf directory: URL) throws -> MailBackfillCounts {
        try Store.withCopy(of: directory) { try $0.previewMailBackfill() }
    }
}
