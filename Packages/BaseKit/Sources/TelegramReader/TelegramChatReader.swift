import Foundation
import LocalSources
import WorkbenchCore

public struct TelegramConsentMissing: LocalizedError, Equatable {
    public let people: [TelegramMember]

    public var errorDescription: String? {
        "Not everyone in this group has agreed yet: \(people.map(\.name).joined(separator: ", ")). Ask them, then confirm again."
    }
}

public struct TelegramChatReader: Sendable {
    private let service: any TelegramService
    private let chat: Int64
    private let agreed: Set<Int64>
    private let policy: any CapturePolicyProvider
    private let me: String

    public init(
        service: any TelegramService, chat: Int64, agreed: Set<Int64>, policy: any CapturePolicyProvider,
        me: String = "You"
    ) {
        self.service = service
        self.chat = chat
        self.agreed = agreed
        self.policy = policy
        self.me = me
    }

    public func members(now: Date = .now) async throws -> [TelegramMember] {
        _ = try await policy.grant(for: .telegram, label: String(chat), at: now)
        return try await service.members(of: chat)
    }

    public func read(from start: Date, to end: Date, now: Date = .now) async throws -> (
        messages: [TelegramMessage], members: [TelegramMember]
    ) {
        let members = try await members(now: now)
        let newcomers = members.filter { !agreed.contains($0.id) }
        guard newcomers.isEmpty else { throw TelegramConsentMissing(people: newcomers) }
        let messages = try await service.messages(in: chat, from: start, to: end, me: me)
            .filter { $0.chat == chat && $0.date >= start && $0.date < end }
            .sorted { ($0.date, $0.id) < ($1.date, $1.id) }
        return (messages, members)
    }
}
