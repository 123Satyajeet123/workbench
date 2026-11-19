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
    public enum Kind: Sendable, Equatable { case text, document, voiceNote }

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
}

/// Reads one chat, named by its WhatsApp ID: the founder's own chat or one group. The policy must allow that ID; no
/// other chat is ever queried.
public struct WhatsAppChatReader: Sendable {
    private enum MessageType {
        static let text = 0
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
                g.ZMEMBERJID, COALESCE(g.ZCONTACTNAME, g.ZFIRSTNAME, p.ZPUSHNAME, g.ZMEMBERJID)
            FROM ZWAMESSAGE m
            JOIN ZWACHATSESSION s ON s.Z_PK = m.ZCHATSESSION
            LEFT JOIN ZWAMEDIAITEM i ON i.ZMESSAGE = m.Z_PK
            LEFT JOIN ZWAGROUPMEMBER g ON g.Z_PK = m.ZGROUPMEMBER
            LEFT JOIN ZWAPROFILEPUSHNAME p ON p.ZJID = g.ZMEMBERJID
            WHERE s.ZCONTACTJID = ? AND s.ZSESSIONTYPE IN (?, ?) AND m.ZMESSAGETYPE IN (?, ?, ?)
                AND m.ZMESSAGEDATE >= ? AND m.ZMESSAGEDATE < ?
            ORDER BY m.ZMESSAGEDATE, m.Z_PK
            """,
            binding: [
                .text(chatJID), .integer(Int64(SessionType.person)), .integer(Int64(SessionType.group)),
                .integer(Int64(MessageType.text)), .integer(Int64(MessageType.voiceNote)),
                .integer(Int64(MessageType.document)),
                .real(start.timeIntervalSinceReferenceDate), .real(end.timeIntervalSinceReferenceDate),
            ])
        return rows.compactMap(entry)
    }

    /// The group's current members. Empty for the founder's own chat.
    public func members(now: Date = .now) async throws -> [WhatsAppMember] {
        _ = try await policy.grant(for: .whatsapp, label: chatJID, at: now)
        let snapshot = try Self.snapshot(container)
        return try snapshot.rows(
            """
            SELECT g.ZMEMBERJID, COALESCE(g.ZCONTACTNAME, g.ZFIRSTNAME, p.ZPUSHNAME, g.ZMEMBERJID)
            FROM ZWAGROUPMEMBER g
            JOIN ZWACHATSESSION s ON s.Z_PK = g.ZCHATSESSION
            LEFT JOIN ZWAPROFILEPUSHNAME p ON p.ZJID = g.ZMEMBERJID
            WHERE s.ZCONTACTJID = ? AND s.ZSESSIONTYPE = ? AND g.ZISACTIVE = 1
            ORDER BY 2
            """,
            binding: [.text(chatJID), .integer(Int64(SessionType.group))]
        ).compactMap { row in row.text(0).map { WhatsAppMember(jid: $0, name: row.text(1) ?? $0) } }
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

    private func entry(_ row: SQLiteRow) -> WhatsAppEntry? {
        let kind: WhatsAppEntry.Kind
        switch Int(row.integer(2)) {
        case MessageType.text: kind = .text
        case MessageType.voiceNote: kind = .voiceNote
        case MessageType.document: kind = .document
        default: return nil
        }
        let sender: WhatsAppSender =
            row.integer(6) != 0 ? .me : .member(jid: row.text(7) ?? "", name: row.text(8) ?? row.text(7) ?? "")
        return WhatsAppEntry(
            id: row.integer(0), date: Date(timeIntervalSinceReferenceDate: row.real(1)), kind: kind, sender: sender,
            text: row.text(3) ?? "", title: row.text(5),
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
