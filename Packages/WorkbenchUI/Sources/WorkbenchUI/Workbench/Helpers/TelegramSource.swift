import CaptureService
import Foundation
import LocalSources
import Observation
import TelegramReader
import WorkbenchCore

struct TelegramConsent: Codable, Equatable {
    var chat: Int64
    var people: [TelegramMember]
    var at: Date
}

@Observable
final class TelegramSource: MachineSource {
    private(set) var chat: TelegramChat?
    private(set) var consent: TelegramConsent?
    private(set) var groups: [TelegramChat] = []
    private(set) var asking: TelegramChat?
    private(set) var askingPeople: [TelegramMember] = []
    private(set) var members: [TelegramMember] = []
    private(set) var isChanging = false
    let account: TelegramAccount

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let capture: CaptureService
    @ObservationIgnored private let founder: () -> String
    @ObservationIgnored private let othersReading: () -> Set<String>
    @ObservationIgnored private let chatKey: StateKey<TelegramChat>
    @ObservationIgnored private let consentKey: StateKey<TelegramConsent>
    @ObservationIgnored private let hear: VoiceHearing

    init(
        store: Store, capture: CaptureService, account: TelegramAccount, task: String,
        founder: @escaping () -> String, othersReading: @escaping () -> Set<String> = { [] },
        hear: @escaping VoiceHearing = VoiceText.texts(in:)
    ) throws {
        self.store = store
        self.hear = hear
        self.capture = capture
        self.account = account
        self.founder = founder
        self.othersReading = othersReading
        chatKey = MachineKey.telegramChat(task)
        consentKey = MachineKey.telegramConsent(task)
        chat = try chatKey.load(from: store)
        consent = try consentKey.load(from: store)
        members = consent?.people ?? []
    }

    var scope: String { chat?.label ?? "" }
    var isReady: Bool { chat != nil && consent?.chat == chat?.id }
    var picks: String? { "a chat" }
    var context: [String: [String]] { ["members": members.map(\.name)] }
    var chosenSummary: String? { chat.map { "Telegram · \($0.title)" } }
    var chosenContainers: [Container] { chat.map { [Container(id: $0.label, kind: .group, title: $0.title)] } ?? [] }

    func loadGroups() async throws {
        try await account.waitUntilReady()
        groups = try await account.service.groups()
    }

    func ask(_ group: TelegramChat) async throws {
        try await account.waitUntilReady()
        askingPeople = try await account.service.members(of: group.id)
        asking = group
    }

    /// Records that everyone in the group agreed, as the store's confirmed audience: lines are written only for that
    /// audience, so a member who joins later stops the reading until everyone is asked again.
    func confirmEveryoneAgreed() throws {
        guard let group = asking else { return }
        guard let audience = TelegramChatReader.audience(of: askingPeople, chat: group.id) else {
            throw TelegramFailure("This group has no other member, so there is no one to ask.")
        }
        try store.agree(audience: audience, kind: .telegram, label: group.label)
        let agreed = TelegramConsent(chat: group.id, people: askingPeople, at: store.clock())
        let dropped = Set([chat?.label].compactMap { $0 }).subtracting([group.label]).subtracting(othersReading())
        try capture.update {
            $0.switches[.telegram] = true
            $0.allowList[.telegram, default: []].subtract(dropped)
            $0.allowList[.telegram, default: []].insert(group.label)
        }
        try chatKey.save(group, to: store)
        try consentKey.save(agreed, to: store)
        chat = group
        consent = agreed
        members = askingPeople
        keep()
    }

    func askAgain() async throws {
        guard let chat else { return }
        isChanging = true
        try await ask(chat)
    }

    func stopReading() throws {
        if let label = chat?.label, !othersReading().contains(label) {
            try capture.update { $0.allowList[.telegram, default: []].remove(label) }
        }
        try chatKey.clear(in: store)
        try consentKey.clear(in: store)
        chat = nil
        consent = nil
        members = []
        keep()
    }

    func change() { isChanging = true }

    func keep() {
        isChanging = false
        groups = []
        asking = nil
        askingPeople = []
    }

    func backToGroups() {
        asking = nil
        askingPeople = []
    }

    /// The day's messages of the group, each a numbered line. The group is first read into the evidence store, which
    /// writes it only for the audience the founder confirmed; the lines come from there, as the proof cards read them.
    func evidence(on day: WorkDay) async throws -> EvidenceSet {
        guard let chat, let consent, consent.chat == chat.id else { return EvidenceSet(lines: []) }
        try await account.waitUntilReady()
        await account.applyDeletions()
        let reader = TelegramChatReader(
            service: account.service, chat: chat.id, agreed: Set(consent.people.map(\.id)), policy: store,
            me: founderLabel(founder()), window: day.start..<day.end, hear: hear)
        let report = try await store.ingest(reader, owner: try capture.owner(), now: store.clock())
        if let failure = report.failures.first { throw failure.error }
        let lines = try store.queries.currentLines(in: [chat.label], from: day.start, to: day.end)
            .filter { !$0.isTombstone }.map { evidence($0, start: day.start) }
        return EvidenceSet(
            lines: lines,
            context: ["members": members.map(\.name) + [founderLabel(founder())], "founder": [founderLabel(founder())]])
    }

    private func evidence(_ stored: StoredLine, start: Date) -> Evidence {
        Evidence(
            id: stored.number, start: stored.time ?? start, line: "\(sender(of: stored)): \(stored.text)",
            quotable: [stored.text], lineID: stored.lineID, provenance: stored.provenance)
    }

    private func sender(of stored: StoredLine) -> String {
        guard let actor = stored.actor else { return "Unknown" }
        if actor == WhatsAppAudience.owner { return founderLabel(founder()) }
        return members.first { TelegramChatReader.actor(of: $0.id) == actor }?.name ?? "Telegram user"
    }
}
