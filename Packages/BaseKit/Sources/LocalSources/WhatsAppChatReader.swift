import Foundation
import WorkbenchCore

public enum WhatsAppMedia: Sendable, Equatable {
    case file(URL)
    case notDownloaded
}

public enum WhatsAppSender: Sendable, Equatable {
    case me
    /// A group member: their WhatsApp ID and the name this Mac knows them by.
    case member(jid: String, name: String)
}

public struct WhatsAppEntry: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case text, photo, document, voiceNote }

    public var id: Int64
    public var date: Date
    public var kind: Kind
    public var sender: WhatsAppSender
    /// The message text, or the caption of a document.
    public var text: String
    public var title: String?
    public var media: WhatsAppMedia?
}

public struct WhatsAppChat: Codable, Sendable, Equatable, Identifiable {
    public var jid: String
    public var name: String
    public var id: String { jid }
}

public struct WhatsAppMember: Sendable, Equatable {
    public var jid: String
    public var name: String

    public init(jid: String, name: String) {
        self.jid = jid
        self.name = name
    }
}

/// Reads one chat, named by its WhatsApp ID: the founder's own chat or one group. The policy must allow that ID; no
/// other chat is ever queried.
public struct WhatsAppChatReader: Sendable {
    private enum MessageType {
        static let text = 0
        static let photo = 1
        static let voiceNote = 3
        static let document = 8
    }

    private enum SessionType {
        static let person = 0
        static let group = 1
    }

    public static var defaultContainer: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Group Containers/group.net.whatsapp.WhatsApp.shared")
    }

    private let container: URL
    public let chatJID: String
    private let policy: any CapturePolicyProvider

    public init(container: URL = defaultContainer, chatJID: String, policy: any CapturePolicyProvider) {
        self.container = container
        self.chatJID = chatJID
        self.policy = policy
    }

    /// The groups on this Mac, by name, so the founder can choose one. Only names and IDs, and only while the WhatsApp
    /// source is on.
    public static func groups(container: URL = defaultContainer, policy: CapturePolicy) throws -> [WhatsAppChat] {
        guard policy.mode != .off else { throw ReadError.denied(.captureOff) }
        guard policy.isEnabled(.whatsapp) else { throw ReadError.denied(.sourceSwitchedOff) }
        let snapshot = try Self.snapshot(container)
        return try snapshot.rows(
            "SELECT ZCONTACTJID, ZPARTNERNAME FROM ZWACHATSESSION WHERE ZSESSIONTYPE = ? AND ZPARTNERNAME IS NOT NULL ORDER BY ZLASTMESSAGEDATE DESC",
            binding: [.integer(Int64(SessionType.group))]
        ).compactMap { row in row.text(0).map { WhatsAppChat(jid: $0, name: row.text(1) ?? $0) } }
    }

    /// Messages of the chat in [start, end), oldest first.
    public func entries(from start: Date = .distantPast, to end: Date = .distantFuture, now: Date = .now)
        async throws -> [WhatsAppEntry]
    {
        _ = try await policy.grant(for: .whatsapp, label: chatJID, at: now)
        let snapshot = try Self.snapshot(container)
        let rows = try snapshot.rows(
            """
            SELECT m.Z_PK, m.ZMESSAGEDATE, m.ZMESSAGETYPE, m.ZTEXT, i.ZMEDIALOCALPATH, i.ZTITLE, m.ZISFROMME,
                g.ZMEMBERJID
            FROM ZWAMESSAGE m
            JOIN ZWACHATSESSION s ON s.Z_PK = m.ZCHATSESSION
            LEFT JOIN ZWAMEDIAITEM i ON i.ZMESSAGE = m.Z_PK
            LEFT JOIN ZWAGROUPMEMBER g ON g.Z_PK = m.ZGROUPMEMBER
            WHERE s.ZCONTACTJID = ? AND s.ZSESSIONTYPE IN (?, ?) AND m.ZMESSAGETYPE IN (?, ?, ?, ?)
                AND m.ZMESSAGEDATE >= ? AND m.ZMESSAGEDATE < ?
            ORDER BY m.ZMESSAGEDATE, m.Z_PK
            """,
            binding: [
                .text(chatJID), .integer(Int64(SessionType.person)), .integer(Int64(SessionType.group)),
                .integer(Int64(MessageType.text)), .integer(Int64(MessageType.photo)),
                .integer(Int64(MessageType.voiceNote)),
                .integer(Int64(MessageType.document)),
                .real(start.timeIntervalSinceReferenceDate), .real(end.timeIntervalSinceReferenceDate),
            ])
        let names = try memberNames(snapshot).names
        return rows.compactMap { entry($0, names: names) }
    }

    /// The group's current members. Empty for the founder's own chat.
    public func members(now: Date = .now) async throws -> [WhatsAppMember] {
        _ = try await policy.grant(for: .whatsapp, label: chatJID, at: now)
        let (names, active) = try memberNames(try Self.snapshot(container))
        return active.compactMap { jid in names[jid].map { WhatsAppMember(jid: jid, name: $0) } }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The name of every member the group ever had, by member ID, and the IDs of its current members. Names come
    /// from the founder's address book as WhatsApp keeps it, then the name a member chose, then WhatsApp's contact
    /// name; see `MemberNames`.
    private func memberNames(_ snapshot: SQLiteSnapshot) throws -> (names: [String: String], active: [String]) {
        let rows = try snapshot.rows(
            """
            SELECT g.ZMEMBERJID, g.ZCONTACTNAME, p.ZPUSHNAME, g.ZISACTIVE
            FROM ZWAGROUPMEMBER g
            JOIN ZWACHATSESSION s ON s.Z_PK = g.ZCHATSESSION
            LEFT JOIN ZWAPROFILEPUSHNAME p ON p.ZJID = g.ZMEMBERJID
            WHERE s.ZCONTACTJID = ? AND s.ZSESSIONTYPE = ?
            """,
            binding: [.text(chatJID), .integer(Int64(SessionType.group))])
        let members = rows.compactMap { row in
            row.text(0).map { (jid: $0, contactName: row.text(1), pushName: row.text(2), active: row.integer(3) == 1) }
        }
        let book = Self.addressBook(container, for: members.map(\.jid))
        let names = MemberNames.resolve(
            members.map { (jid: $0.jid, candidates: [book[$0.jid], $0.pushName, $0.contactName]) })
        return (names, members.filter(\.active).map(\.jid))
    }

    /// Names from the founder's address book, by member ID, as WhatsApp keeps them in `ContactsV2.sqlite`. Empty
    /// when WhatsApp keeps none or changed the layout: then push names stand in.
    private static func addressBook(_ container: URL, for jids: [String]) -> [String: String] {
        guard !jids.isEmpty,
            let snapshot = try? SQLiteSnapshot(copying: container.appending(path: "ContactsV2.sqlite").path),
            (try? snapshot.requireColumns(["ZLID", "ZWHATSAPPID", "ZFULLNAME"], in: "ZWAADDRESSBOOKCONTACT")) != nil
        else { return [:] }
        let marks = Array(repeating: "?", count: jids.count).joined(separator: ",")
        let rows =
            (try? snapshot.rows(
                """
                SELECT ZLID, ZWHATSAPPID, ZFULLNAME FROM ZWAADDRESSBOOKCONTACT
                WHERE ZLID IN (\(marks)) OR ZWHATSAPPID IN (\(marks))
                """, binding: (jids + jids).map { .text($0) })) ?? []
        var book: [String: String] = [:]
        for row in rows {
            guard let name = row.text(2) else { continue }
            for jid in [row.text(0), row.text(1)].compactMap({ $0 }) where !jid.isEmpty { book[jid] = name }
        }
        return book
    }

    private static func snapshot(_ container: URL) throws -> SQLiteSnapshot {
        let snapshot = try SQLiteSnapshot(copying: container.appending(path: "ChatStorage.sqlite").path)
        try snapshot.requireColumns(
            ["Z_PK", "ZCONTACTJID", "ZSESSIONTYPE", "ZPARTNERNAME", "ZLASTMESSAGEDATE"], in: "ZWACHATSESSION")
        try snapshot.requireColumns(
            ["Z_PK", "ZCHATSESSION", "ZMESSAGEDATE", "ZMESSAGETYPE", "ZTEXT", "ZISFROMME", "ZGROUPMEMBER"],
            in: "ZWAMESSAGE")
        try snapshot.requireColumns(["ZMESSAGE", "ZMEDIALOCALPATH", "ZTITLE"], in: "ZWAMEDIAITEM")
        try snapshot.requireColumns(
            ["Z_PK", "ZCHATSESSION", "ZMEMBERJID", "ZCONTACTNAME", "ZFIRSTNAME", "ZISACTIVE"], in: "ZWAGROUPMEMBER")
        try snapshot.requireColumns(["ZJID", "ZPUSHNAME"], in: "ZWAPROFILEPUSHNAME")
        return snapshot
    }

    private func entry(_ row: SQLiteRow, names: [String: String]) -> WhatsAppEntry? {
        let kind: WhatsAppEntry.Kind
        switch Int(row.integer(2)) {
        case MessageType.text: kind = .text
        case MessageType.photo: kind = .photo
        case MessageType.voiceNote: kind = .voiceNote
        case MessageType.document: kind = .document
        default: return nil
        }
        let jid = row.text(7) ?? ""
        let sender: WhatsAppSender =
            row.integer(6) != 0 ? .me : .member(jid: jid, name: names[jid] ?? MemberNames.fallback(for: jid))
        return WhatsAppEntry(
            id: row.integer(0), date: Date(timeIntervalSinceReferenceDate: row.real(1)), kind: kind, sender: sender,
            text: MemberNames.mentions(in: row.text(3) ?? "", names: names), title: row.text(5),
            media: kind == .text ? nil : media(atRelativePath: row.text(4)))
    }

    /// A path counts only when the file exists inside the container's `Message` folder.
    private func media(atRelativePath path: String?) -> WhatsAppMedia {
        guard let path, !path.isEmpty else { return .notDownloaded }
        let root = container.appending(path: "Message").resolvingSymlinksInPath()
        let file = root.appending(path: path).resolvingSymlinksInPath()
        guard file.path.hasPrefix(root.path + "/"), FileManager.default.fileExists(atPath: file.path) else {
            return .notDownloaded
        }
        return .file(file)
    }
}

/// How a member is named to the founder. WhatsApp now keeps many members by a privacy ID (`…@lid`) with empty
/// contact names, so an empty string counts as no name, and the first-name column, which can hold encoded data, is
/// never used. Two members with one name get the end of their ID, so a board never merges two people.
enum MemberNames {
    /// The first non-empty candidate, in order, for each member.
    static func resolve(_ members: [(jid: String, candidates: [String?])]) -> [String: String] {
        let named = members.map { member in
            let name = member.candidates.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            return (jid: member.jid, name: name ?? fallback(for: member.jid))
        }
        let counts = Dictionary(named.map { ($0.name, 1) }, uniquingKeysWith: +)
        return Dictionary(
            named.map { ($0.jid, counts[$0.name, default: 0] > 1 ? "\($0.name) ·\(tail($0.jid))" : $0.name) },
            uniquingKeysWith: { first, _ in first })
    }

    static func fallback(for jid: String) -> String { "Member ·\(tail(jid))" }

    /// `@` followed by a member's ID number, as WhatsApp writes a mention, becomes `@` and their name.
    static func mentions(in text: String, names: [String: String]) -> String {
        text.replacing(#/@(\d{5,})/#) { match in
            let number = String(match.output.1)
            guard let name = names["\(number)@lid"] ?? names["\(number)@s.whatsapp.net"] else {
                return String(match.output.0)
            }
            return "@\(name)"
        }
    }

    private static func tail(_ jid: String) -> String { String(jid.prefix { $0 != "@" }.suffix(4)) }
}
