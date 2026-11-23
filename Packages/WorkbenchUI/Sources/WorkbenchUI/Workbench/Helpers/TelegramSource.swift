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
    var context: [String: [String]] { ["members": members.map(\.name)] }

    func loadGroups() async throws {
        try await account.waitUntilReady()
        groups = try await account.service.groups()
    }

    func ask(_ group: TelegramChat) async throws {
        try await account.waitUntilReady()
        askingPeople = try await account.service.members(of: group.id)
        asking = group
    }

    func confirmEveryoneAgreed() throws {
        guard let group = asking else { return }
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

    func evidence(on day: WorkDay) async throws -> EvidenceSet {
        guard let chat, let consent, consent.chat == chat.id else { return EvidenceSet(lines: []) }
        try await account.waitUntilReady()
        let reader = TelegramChatReader(
            service: account.service, chat: chat.id, agreed: Set(consent.people.map(\.id)), policy: store,
            me: founderLabel(founder()))
        let (messages, people) = try await reader.read(from: day.start, to: day.end)
        members = people
        let voices = await hear(messages.compactMap(\.voice))
        let lines = messages.compactMap { line($0, voices: voices) }
        return EvidenceSet(
            lines: lines,
            context: ["members": people.map(\.name) + [founderLabel(founder())], "founder": [founderLabel(founder())]])
    }

    private func line(_ message: TelegramMessage, voices: [URL: String]) -> Evidence? {
        let heard = message.voice.flatMap { voices[$0] }.flatMap { $0.isEmpty ? nil : "\(VoiceText.tag) \($0)" }
        let text = [heard, message.title, message.text].compactMap { $0 }.filter { !$0.isEmpty }
            .joined(separator: " — ")
        guard !text.isEmpty else { return nil }
        let sender = message.isOutgoing ? founderLabel(founder()) : message.sender
        return Evidence(id: message.id, start: message.date, line: "\(sender): \(text)", quotable: [text])
    }
}
