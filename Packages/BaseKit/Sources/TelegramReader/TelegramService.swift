import Foundation
import LocalSources
import WorkbenchCore

public struct TelegramChat: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: Int64
    public var title: String
    public var memberCount: Int

    public init(id: Int64, title: String, memberCount: Int) {
        self.id = id
        self.title = title
        self.memberCount = memberCount
    }

    public var label: String { String(id) }
}

public struct TelegramMember: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: Int64
    public var name: String

    public init(id: Int64, name: String) {
        self.id = id
        self.name = name
    }
}

public struct TelegramMessage: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case text, photo, video, document, voiceNote }

    public var id: Int64
    public var chat: Int64
    public var date: Date
    public var kind: Kind
    public var sender: String
    public var isOutgoing: Bool
    public var text: String
    public var title: String?

    public init(
        id: Int64, chat: Int64, date: Date, kind: Kind, sender: String, isOutgoing: Bool, text: String,
        title: String? = nil
    ) {
        self.id = id
        self.chat = chat
        self.date = date
        self.kind = kind
        self.sender = sender
        self.isOutgoing = isOutgoing
        self.text = text
        self.title = title
    }
}

public enum TelegramLogin: Sendable, Equatable {
    case signedOut
    case connecting
    case scan(link: String)
    case password(hint: String)
    case ready(name: String)
    case paused
    case failed(String)
}

public struct TelegramKeys: Sendable, Equatable {
    public var apiID: Int
    public var apiHash: String
    public var databaseKey: Data

    public init(apiID: Int, apiHash: String, databaseKey: Data) {
        self.apiID = apiID
        self.apiHash = apiHash
        self.databaseKey = databaseKey
    }
}

public struct TelegramFailure: LocalizedError, Equatable {
    public let message: String

    public init(_ message: String) { self.message = message }

    public var errorDescription: String? { message }
}

public protocol TelegramService: AnyObject, Sendable {
    func connect(_ keys: TelegramKeys, policy: CapturePolicy, onChange: @escaping @Sendable (TelegramLogin) -> Void)
        throws
    func checkPassword(_ password: String) async throws
    func groups() async throws -> [TelegramChat]
    func members(of chat: Int64) async throws -> [TelegramMember]
    func messages(in chat: Int64, from start: Date, to end: Date, me: String) async throws -> [TelegramMessage]
    func signOut() async throws
    func disconnect()
}

public enum TelegramGate {
    public static func check(_ policy: CapturePolicy) throws {
        guard policy.mode != .off else { throw ReadError.denied(.captureOff) }
        guard policy.isEnabled(.telegram) else { throw ReadError.denied(.sourceSwitchedOff) }
    }
}
