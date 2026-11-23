import Foundation
import Kernel
import Lines
import LocalSources
import WorkbenchCore

public struct TelegramConsentMissing: LocalizedError, Equatable {
    public let people: [TelegramMember]

    public var errorDescription: String? {
        "Not everyone in this group has agreed yet: \(people.map(\.name).joined(separator: ", ")). Ask them, then confirm again."
    }
}

/// One Telegram group as an evidence source. A read gives the group's lines in a window of days and its audience, and
/// `Store.ingest` writes them under the consent check of the write transaction. A group is read only when no member is
/// outside the people who agreed, and the store refuses a write whose audience is not the one confirmed.
public struct TelegramChatReader: EvidenceSource {
    public static let readerVersion = "telegram-tdlib 1"

    private let service: any TelegramService
    private let chat: Int64
    private let agreed: Set<Int64>
    private let policy: any CapturePolicyProvider
    private let me: String
    private let window: Range<Date>
    /// Hears the voice notes a read brings, on this Mac.
    private let hear: VoiceHearing

    public var descriptor: SourceDescriptor { .telegramChat }

    public init(
        service: any TelegramService, chat: Int64, agreed: Set<Int64>, policy: any CapturePolicyProvider,
        me: String = "You", window: Range<Date> = .distantPast..<Date.distantFuture,
        hear: @escaping VoiceHearing = VoiceText.texts(in:)
    ) {
        self.service = service
        self.chat = chat
        self.agreed = agreed
        self.policy = policy
        self.me = me
        self.window = window
        self.hear = hear
    }

    /// The actor of a member's lines, and the name of a member in the audience.
    public static func actor(of member: Int64) -> String { "telegram:\(member)" }

    /// Everyone who can read the group: the people given, and the owner. Nil for a group with nobody else, which no
    /// line may come from.
    public static func audience(of members: [TelegramMember], chat: Int64) -> AudienceDigest? {
        AudienceRule.digest(
            of: Container(id: String(chat), kind: .group, title: ""), owner: WhatsAppAudience.owner,
            membership: Membership(members: members.map { actor(of: $0.id) }, proof: .sourceService))
    }

    public func members(now: Date = .now) async throws -> [TelegramMember] {
        _ = try await policy.grant(for: .telegram, label: String(chat), at: now)
        return try await service.members(of: chat)
    }

    /// Telegram lists its groups through the account, which needs a sign-in, so this source sees none by itself.
    public func sightings(policy: CapturePolicy, now: Date) throws -> [ContainerSighting] { [] }

    public func observe(state: @Sendable (String) throws -> ScanState, now: Date) async throws -> SourceRead {
        let label = String(chat)
        do {
            let grant = try await policy.grant(for: .telegram, label: label, at: now)
            let members = try await service.members(of: chat)
            let newcomers = members.filter { !agreed.contains($0.id) }
            guard newcomers.isEmpty else { throw TelegramConsentMissing(people: newcomers) }
            guard let audience = Self.audience(of: members, chat: chat) else { throw ReadError.audienceUnknown }
            let messages = try await service.messages(in: chat, from: window.lowerBound, to: window.upperBound, me: me)
            let kept = messages.filter { $0.chat == chat && window.contains($0.date) }
            let voices = await hear(kept.compactMap(\.voice))
            let lines = kept.compactMap { observedLine($0, voices: voices) }
            return SourceRead(
                readings: [
                    SourceReading(
                        grant: grant, label: label, container: label, audience: audience, lines: lines,
                        cursorAfter: nil, readerVersion: Self.readerVersion)
                ])
        } catch {
            return SourceRead(failures: [LabelFailure(label: label, error: error)])
        }
    }

    /// A voice note's words are what was said in it, heard on this Mac (`VoiceText`), before its caption.
    private func observedLine(_ message: TelegramMessage, voices: [URL: String]) -> ObservedLine? {
        let heard = VoiceText.line(heard: message.voice.flatMap { voices[$0] })
        let text = [heard, message.title, message.text].compactMap { $0 }.filter { !$0.isEmpty }
            .joined(separator: " — ")
        guard !text.isEmpty,
            let key = try? EntityKey.telegram(chatID: chat, messageID: message.id)
        else { return nil }
        return ObservedLine(
            line: Line(entity: key, text: text, readerVersion: Self.readerVersion), quality: .stable,
            eventTime: UTCInstant(message.date),
            actor: message.isOutgoing ? WhatsAppAudience.owner : Self.actor(of: message.senderID),
            messageRef: String(message.id))
    }
}
