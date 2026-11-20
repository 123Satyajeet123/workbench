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
    /// The chat it was sent in: a group or a direct chat.
    public var chat: String
    public var date: Date
    public var kind: Kind
    public var sender: WhatsAppSender
    /// The message text, or the caption of a document.
    public var text: String
    public var title: String?
    public var media: WhatsAppMedia?
}

public struct WhatsAppChat: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var jid: String
    public var name: String
    public var id: String { jid }
    /// WhatsApp names groups `…@g.us`; a direct chat is the other person's id.
    public var isGroup: Bool { jid.hasSuffix("@g.us") }
}

/// Which chats a several-chat machine reads, as the founder put it: groups whose name holds some words, and the direct
/// chats with people in those groups.
public struct ChatSelection: Codable, Sendable, Equatable {
    public var nameContains: String
    public var directWithMembers: Bool

    public init(nameContains: String, directWithMembers: Bool) {
        self.nameContains = nameContains
        self.directWithMembers = directWithMembers
    }
}

public struct WhatsAppMember: Codable, Sendable, Equatable {
    public var jid: String
    public var name: String
    /// The IDs of the chosen chats the person is in now; nil for a person stored before this was kept.
    public var chats: [String]?

    public init(jid: String, name: String, chats: [String]? = nil) {
        self.jid = jid
        self.name = name
        self.chats = chats
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
    /// The chats this reader may read; the policy must allow each one.
    public let chatJIDs: [String]
    private let policy: any CapturePolicyProvider

    public init(container: URL = defaultContainer, chatJIDs: [String], policy: any CapturePolicyProvider) {
        self.container = container
        self.chatJIDs = chatJIDs
        self.policy = policy
    }

    public init(container: URL = defaultContainer, chatJID: String, policy: any CapturePolicyProvider) {
        self.init(container: container, chatJIDs: [chatJID], policy: policy)
    }

    /// The chats that match a selection: groups whose name holds its words, and, when asked, direct chats with people
    /// in those groups. Only names and IDs, and only while the WhatsApp source is on.
    public static func chats(
        matching selection: ChatSelection, container: URL = defaultContainer, policy: CapturePolicy
    ) throws -> [WhatsAppChat] {
        guard policy.mode != .off else { throw ReadError.denied(.captureOff) }
        guard policy.isEnabled(.whatsapp) else { throw ReadError.denied(.sourceSwitchedOff) }
        let words = selection.nameContains.trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty else { return [] }
        let snapshot = try Self.snapshot(container)
        let groups = try snapshot.rows(
            """
            SELECT ZCONTACTJID, ZPARTNERNAME FROM ZWACHATSESSION
            WHERE ZSESSIONTYPE = ? AND ZPARTNERNAME IS NOT NULL AND instr(lower(ZPARTNERNAME), lower(?)) > 0
            ORDER BY ZLASTMESSAGEDATE DESC
            """, binding: [.integer(Int64(SessionType.group)), .text(words)]
        ).compactMap { row in row.text(0).map { WhatsAppChat(jid: $0, name: row.text(1) ?? $0) } }
        guard selection.directWithMembers, !groups.isEmpty else { return groups }
        let marks = Array(repeating: "?", count: groups.count).joined(separator: ",")
        let direct = try snapshot.rows(
            """
            SELECT s.ZCONTACTJID, s.ZPARTNERNAME FROM ZWACHATSESSION s
            WHERE s.ZSESSIONTYPE = ? AND s.ZCONTACTJID IN (
                SELECT g.ZMEMBERJID FROM ZWAGROUPMEMBER g JOIN ZWACHATSESSION c ON c.Z_PK = g.ZCHATSESSION
                WHERE c.ZCONTACTJID IN (\(marks)))
            ORDER BY s.ZLASTMESSAGEDATE DESC
            """, binding: [.integer(Int64(SessionType.person))] + groups.map { .text($0.jid) }
        ).compactMap { row in row.text(0).map { WhatsAppChat(jid: $0, name: row.text(1) ?? $0) } }
        return groups + direct
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

    /// Messages of the chats in [start, end), oldest first.
    public func entries(from start: Date = .distantPast, to end: Date = .distantFuture, now: Date = .now)
        async throws -> [WhatsAppEntry]
    {
        try await read(from: start, to: end, now: now).entries
    }

    /// The people in the chats now: the groups' members and the other person of each direct chat.
    public func members(now: Date = .now) async throws -> [WhatsAppMember] {
        try await read(from: .distantFuture, to: .distantFuture, now: now).members
    }

    /// The messages of the chats in [start, end) and the people in them, from one copy of WhatsApp's database: a copy
    /// per chat would copy the whole database dozens of times for a several-chat machine.
    public func read(from start: Date, to end: Date, now: Date = .now) async throws -> (
        entries: [WhatsAppEntry], members: [WhatsAppMember]
    ) {
        for chat in chatJIDs { _ = try await policy.grant(for: .whatsapp, label: chat, at: now) }
        guard !chatJIDs.isEmpty else { return ([], []) }
        let snapshot = try Self.snapshot(container)
        let marks = Array(repeating: "?", count: chatJIDs.count).joined(separator: ",")
        let rows = try snapshot.rows(
            """
            SELECT m.Z_PK, m.ZMESSAGEDATE, m.ZMESSAGETYPE, m.ZTEXT, i.ZMEDIALOCALPATH, i.ZTITLE, m.ZISFROMME,
                g.ZMEMBERJID, s.ZCONTACTJID, s.ZSESSIONTYPE
            FROM ZWAMESSAGE m
            JOIN ZWACHATSESSION s ON s.Z_PK = m.ZCHATSESSION
            LEFT JOIN ZWAMEDIAITEM i ON i.ZMESSAGE = m.Z_PK
            LEFT JOIN ZWAGROUPMEMBER g ON g.Z_PK = m.ZGROUPMEMBER
            WHERE s.ZCONTACTJID IN (\(marks)) AND s.ZSESSIONTYPE IN (?, ?) AND m.ZMESSAGETYPE IN (?, ?, ?, ?)
                AND m.ZMESSAGEDATE >= ? AND m.ZMESSAGEDATE < ?
            ORDER BY m.ZMESSAGEDATE, m.Z_PK
            """,
            binding: chatJIDs.map { .text($0) } + [
                .integer(Int64(SessionType.person)), .integer(Int64(SessionType.group)),
                .integer(Int64(MessageType.text)), .integer(Int64(MessageType.photo)),
                .integer(Int64(MessageType.voiceNote)), .integer(Int64(MessageType.document)),
                .real(start.timeIntervalSinceReferenceDate), .real(end.timeIntervalSinceReferenceDate),
            ])
        let (names, active, chats) = try memberNames(snapshot)
        let members = active.compactMap { jid in
            names[jid].map { WhatsAppMember(jid: jid, name: $0, chats: chats[jid, default: []]) }
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return (rows.compactMap { entry($0, names: names) }, members)
    }

    /// The name of everyone in the chats, by ID, the IDs of those in them now, and the chats each of those is in now:
    /// every member a group ever had, and the other person of each direct chat. Names come from the founder's address book as WhatsApp keeps it, then
    /// the name a person chose, then WhatsApp's contact name; see `MemberNames`.
    private func memberNames(_ snapshot: SQLiteSnapshot) throws -> (
        names: [String: String], active: [String], chats: [String: [String]]
    ) {
        let marks = Array(repeating: "?", count: chatJIDs.count).joined(separator: ",")
        let groupRows = try snapshot.rows(
            """
            SELECT g.ZMEMBERJID, g.ZCONTACTNAME, p.ZPUSHNAME, g.ZISACTIVE, s.ZCONTACTJID
            FROM ZWAGROUPMEMBER g
            JOIN ZWACHATSESSION s ON s.Z_PK = g.ZCHATSESSION
            LEFT JOIN ZWAPROFILEPUSHNAME p ON p.ZJID = g.ZMEMBERJID
            WHERE s.ZCONTACTJID IN (\(marks)) AND s.ZSESSIONTYPE = ?
            """,
            binding: chatJIDs.map { .text($0) } + [.integer(Int64(SessionType.group))])
        let directRows = try snapshot.rows(
            """
            SELECT s.ZCONTACTJID, s.ZPARTNERNAME, p.ZPUSHNAME, 1, s.ZCONTACTJID FROM ZWACHATSESSION s
            LEFT JOIN ZWAPROFILEPUSHNAME p ON p.ZJID = s.ZCONTACTJID
            WHERE s.ZCONTACTJID IN (\(marks)) AND s.ZSESSIONTYPE = ?
            """,
            binding: chatJIDs.map { .text($0) } + [.integer(Int64(SessionType.person))])
        // One person per ID, in whichever chats: in a chat now if in any of them now.
        var byID: [String: (jid: String, contactName: String?, pushName: String?, active: Bool)] = [:]
        var order: [String] = []
        var chats: [String: [String]] = [:]
        for row in groupRows + directRows {
            guard let jid = row.text(0) else { continue }
            if row.integer(3) == 1, let chat = row.text(4), !chats[jid, default: []].contains(chat) {
                chats[jid, default: []].append(chat)
            }
            if let known = byID[jid] {
                byID[jid] = (
                    jid, known.contactName ?? row.text(1), known.pushName ?? row.text(2),
                    known.active || row.integer(3) == 1
                )
            } else {
                byID[jid] = (jid, row.text(1), row.text(2), row.integer(3) == 1)
                order.append(jid)
            }
        }
        let members = order.compactMap { byID[$0] }
        let book = Self.addressBook(container, for: members.map(\.jid))
        let names = MemberNames.resolve(
            members.map { (jid: $0.jid, candidates: [book[$0.jid], $0.pushName, $0.contactName]) })
        return (names, members.filter(\.active).map(\.jid), chats)
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
        // In a direct chat a received message has no group member: it is from the other person of the chat.
        let chat = row.text(8) ?? ""
        let jid = row.text(7) ?? (Int(row.integer(9)) == SessionType.person ? chat : "")
        let sender: WhatsAppSender =
            row.integer(6) != 0 ? .me : .member(jid: jid, name: names[jid] ?? MemberNames.fallback(for: jid))
        return WhatsAppEntry(
            id: row.integer(0), chat: chat, date: Date(timeIntervalSinceReferenceDate: row.real(1)), kind: kind,
            sender: sender,
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
    /// The first candidate that holds a letter or a digit, in order, for each member: a name such as "." or "🙂"
    /// names nobody, so it falls back like an empty one.
    static func resolve(_ members: [(jid: String, candidates: [String?])]) -> [String: String] {
        let named = members.map { member in
            let name = member.candidates.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { $0.unicodeScalars.contains(where: CharacterSet.alphanumerics.contains) }
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
