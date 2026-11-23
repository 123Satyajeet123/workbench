import CaptureService
import Foundation
import LocalSources
import Observation
import WorkbenchCore

@Observable
final class WhatsAppSource: MachineSource {
    private(set) var chats: [WhatsAppChat] = []
    private(set) var groups: [WhatsAppChat] = []
    private(set) var matching: [WhatsAppChat] = []
    private(set) var members: [WhatsAppMember] = []
    private(set) var teamHandles: Set<String> = []
    private(set) var isChanging = false
    private(set) var readsEveryChat = false

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let capture: CaptureService
    @ObservationIgnored private let founder: () -> String
    @ObservationIgnored private let container: URL
    @ObservationIgnored private let othersReading: () -> Set<String>
    @ObservationIgnored private let chatsKey: StateKey<[WhatsAppChat]>
    @ObservationIgnored private let membersKey: StateKey<[WhatsAppMember]>
    @ObservationIgnored private let everyChatKey: StateKey<Bool>
    @ObservationIgnored private let hear: VoiceHearing

    init(
        store: Store, capture: CaptureService, task: String, founder: @escaping () -> String,
        container: URL = WhatsAppChatReader.defaultContainer, othersReading: @escaping () -> Set<String> = { [] },
        hear: @escaping VoiceHearing = VoiceText.texts(in:)
    ) throws {
        self.store = store
        self.hear = hear
        self.othersReading = othersReading
        self.capture = capture
        self.founder = founder
        self.container = container
        chatsKey = MachineKey.chats(task)
        membersKey = MachineKey.members(task)
        everyChatKey = MachineKey.everyChat(task)
        readsEveryChat = try everyChatKey.load(from: store) ?? false
        chats = try chatsKey.load(from: store) ?? []
        members = try membersKey.load(from: store) ?? []
        try loadTeamHandles()
    }

    var chat: WhatsAppChat? { chats.count == 1 ? chats.first : nil }
    var isSeveral: Bool { chats.count > 1 }

    var scope: String { chat?.jid ?? "" }
    var isReady: Bool { !chats.isEmpty }
    var expectedPeople: [WhatsAppMember] {
        let team = members.filter(isTeammate)
        guard team.isEmpty else { return team }
        guard isSeveral else { return members }
        guard let first = chats.first(where: \.isGroup) ?? chats.first else { return [] }
        return members.filter { $0.chats?.contains(first.jid) == true }
    }

    var context: [String: [String]] { ["members": expectedPeople.map(\.name)] }
    var grantLabels: [String?] { isSeveral ? chats.map(\.jid) : [scope.isEmpty ? nil : scope] }

    func loadGroups() throws {
        try switchOn()
        groups = try WhatsAppChatReader.groups(container: container, policy: capture.policy)
    }

    func preview(_ selection: ChatSelection) throws {
        try switchOn()
        matching = try WhatsAppChatReader.chats(matching: selection, container: container, policy: capture.policy)
    }

    func choose(_ group: WhatsAppChat) throws { try choose([group]) }

    func chooseEveryChat() throws {
        try switchOn()
        try choose(WhatsAppChatReader.everyChat(container: container, policy: capture.policy), everyChat: true)
    }

    func choose(_ chosen: [WhatsAppChat]) throws { try choose(chosen, everyChat: false) }

    private func choose(_ chosen: [WhatsAppChat], everyChat: Bool) throws {
        let dropped = Set(chats.map(\.jid)).subtracting(chosen.map(\.jid)).subtracting(othersReading())
        try capture.update {
            $0.switches[.whatsapp] = true
            $0.allowList[.whatsapp, default: []].subtract(dropped)
            $0.allowList[.whatsapp, default: []].formUnion(chosen.map(\.jid))
        }
        try chatsKey.save(chosen, to: store)
        try everyChatKey.save(everyChat, to: store)
        chats = chosen
        readsEveryChat = everyChat
        keep()
    }

    func change() { isChanging = true }

    func keep() {
        isChanging = false
        groups = []
        matching = []
    }

    func isTeammate(_ member: WhatsAppMember) -> Bool { teamHandles.contains(member.jid) }

    func setTeammate(_ member: WhatsAppMember, on: Bool) throws {
        if on {
            try store.addTeammate(member.name, whatsapp: member.jid)
        } else {
            try store.removeTeammate(whatsapp: member.jid)
        }
        try loadTeamHandles()
    }

    /// The people in the chats as WhatsApp has them now. Reading WhatsApp's data can make macOS ask the founder again
    /// (measured: 7 "access data from other apps" prompts in one day), so only checks that must be live use this.
    func loadMembers() async throws {
        guard !chats.isEmpty else { return }
        try remember(try await reader().members())
    }

    func showMembers() async throws {
        if members.isEmpty { try await loadMembers() }
    }

    private func switchOn() throws {
        if !capture.policy.isEnabled(.whatsapp) { try capture.update { $0.switches[.whatsapp] = true } }
    }

    private func remember(_ current: [WhatsAppMember]) throws {
        members = current
        try membersKey.save(current, to: store)
        try loadTeamHandles()
    }

    private func loadTeamHandles() throws {
        let people = Set((try store.queries.team()?.people ?? []).filter { !$0.isMe }.compactMap(\.id))
        teamHandles = Set(try store.queries.whatsappLinks().filter { people.contains($0.key) }.values)
    }

    func evidence(on day: WorkDay) async throws -> EvidenceSet {
        guard !chats.isEmpty else { return EvidenceSet(lines: []) }
        if readsEveryChat { try takeInNewChats() }
        let (entries, people) = try await reader().read(from: day.start, to: day.end)
        try remember(people)
        let photos = await ImageText.texts(in: entries.compactMap(\.photo))
        let voices = await hear(entries.compactMap(\.voice))
        let names = Dictionary(chats.map { ($0.jid, $0.name) }, uniquingKeysWith: { first, _ in first })
        let lines = entries.compactMap { entry in
            line(entry, photos: photos, voices: voices).map { line in
                guard isSeveral, let chat = names[entry.chat] else { return line }
                var named = line
                named.line = "[\(chat)] " + line.line
                return named
            }
        }
        return EvidenceSet(
            lines: lines,
            context: ["members": members.map(\.name) + [founderLabel(founder())], "founder": [founderLabel(founder())]])
    }

    private func takeInNewChats() throws {
        let every = try WhatsAppChatReader.everyChat(container: container, policy: capture.policy)
        guard Set(every.map(\.jid)) != Set(chats.map(\.jid)) else { return }
        try capture.update { $0.allowList[.whatsapp, default: []].formUnion(every.map(\.jid)) }
        try chatsKey.save(every, to: store)
        chats = every
    }

    private func reader() -> WhatsAppChatReader {
        WhatsAppChatReader(container: container, chatJIDs: chats.map(\.jid), policy: store, me: founderLabel(founder()))
    }

    private func line(_ entry: WhatsAppEntry, photos: [URL: String], voices: [URL: String]) -> Evidence? {
        var parts = [entry.title, entry.text].compactMap { $0 }.filter { !$0.isEmpty }
        if let url = entry.photo, let seen = photos[url], !seen.isEmpty { parts.insert("[photo] \(seen)", at: 0) }
        if let url = entry.voice, let heard = voices[url], !heard.isEmpty {
            parts.insert("\(VoiceText.tag) \(heard)", at: 0)
        }
        let text = parts.joined(separator: " — ")
        guard !text.isEmpty else { return nil }
        let sender: String
        switch entry.sender {
        case .me: sender = founderLabel(founder())
        case .member(_, let name): sender = name
        }
        return Evidence(id: entry.id, start: entry.date, line: "\(sender): \(text)", quotable: [text])
    }
}

func founderLabel(_ name: String) -> String { name.isEmpty ? "You" : "\(name) (You)" }

typealias VoiceHearing = @Sendable ([URL]) async -> [URL: String]

extension VoiceText {
    static let tag = "[voice note]"
}

extension WhatsAppEntry {
    fileprivate var photo: URL? {
        guard kind == .photo, case .file(let url) = media else { return nil }
        return url
    }

    fileprivate var voice: URL? {
        guard kind == .voiceNote, case .file(let url) = media else { return nil }
        return url
    }
}
