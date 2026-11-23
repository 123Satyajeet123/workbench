import CaptureService
import Foundation
import LocalSources
import Observation
import WorkbenchCore

/// The WhatsApp chats a machine reads: one group the founder chose, or several chats chosen by a rule (groups whose
/// name holds some words, and direct chats with their members). Choosing is the consent: these chats, and no other,
/// may be read.
@Observable
final class WhatsAppSource: MachineSource {
    private(set) var chats: [WhatsAppChat] = []
    /// What every source sees now, one entry for each chat, with the sources that saw it.
    private(set) var candidates: [ContainerCandidate] = []
    private(set) var groups: [WhatsAppChat] = []
    private(set) var direct: [WhatsAppChat] = []
    private(set) var matching: [WhatsAppChat] = []
    /// Why the Mac's own WhatsApp data could not be listed, in words; nil when it could.
    private(set) var pullProblem: String?
    private(set) var members: [WhatsAppMember] = []
    private(set) var teamHandles: Set<String> = []
    private(set) var isChanging = false
    /// The name of every person the chats ever had, by WhatsApp ID, as of the last read of the people.
    @ObservationIgnored private var names: [String: String] = [:]
    private(set) var readsEveryChat = false

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let capture: CaptureService
    @ObservationIgnored private let founder: () -> String
    @ObservationIgnored private let container: URL
    @ObservationIgnored private var pulled: [ContainerSighting] = []
    @ObservationIgnored private let chatsKey: StateKey<[WhatsAppChat]>
    @ObservationIgnored private let membersKey: StateKey<[WhatsAppMember]>
    @ObservationIgnored private let everyChatKey: StateKey<Bool>
    @ObservationIgnored private let hear: VoiceHearing

    init(
        store: Store, capture: CaptureService, task: String, founder: @escaping () -> String,
        container: URL = WhatsAppChatReader.defaultContainer, hear: @escaping VoiceHearing = VoiceText.texts(in:)
    ) throws {
        self.store = store
        self.hear = hear
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
    var picks: String? { "chats" }
    /// The people the founder expects to hear from: the teammates ticked on Pip's page or set up in Team setup, when
    /// any is linked to a WhatsApp ID. Otherwise everyone in one chat, or the people in the first of several chats.
    var expectedPeople: [WhatsAppMember] {
        let team = members.filter(isTeammate)
        guard team.isEmpty else { return team }
        guard isSeveral else { return members }
        guard let first = chats.first(where: \.isGroup) ?? chats.first else { return [] }
        return members.filter { $0.chats?.contains(first.jid) == true }
    }

    var context: [String: [String]] { ["members": expectedPeople.map(\.name)] }
    /// With several chats, each one of them must be allowed.
    var grantLabels: [String?] { isSeveral ? chats.map(\.jid) : [scope.isEmpty ? nil : scope] }

    /// Chats to choose from, from every source that sees any: the Mac's WhatsApp data. Listing needs the WhatsApp
    /// switch on; no chat is readable until one is chosen, and nothing is stored until then.
    func loadGroups() throws {
        try switchOn()
        do {
            pulled = try reader(chatJIDs: []).sightings(policy: capture.policy, now: store.clock())
            pullProblem = nil
        } catch {
            pulled = []
            pullProblem = error.localizedDescription
        }
        showCandidates()
    }

    /// The chats a rule chooses among everything the sources see, to show before the founder confirms.
    func preview(_ selection: ChatSelection) throws {
        try loadGroups()
        matching = selection.choose(from: candidates).map(WhatsAppChat.init)
    }

    /// Ends the question the chooser asked: what the sources told is dropped.
    func closeDiscovery() {
        pulled = []
        showCandidates()
    }

    private func showCandidates() {
        candidates = ContainerCandidates.merge(pulled)
        groups = candidates.filter { $0.container.kind == .group }.map(WhatsAppChat.init)
        direct = candidates.filter { $0.container.kind == .direct }.map(WhatsAppChat.init)
    }

    func choose(_ group: WhatsAppChat) throws { try choose([group]) }

    func chooseEveryChat() throws {
        try loadGroups()
        try choose(groups + direct, everyChat: true)
    }

    func choose(_ chosen: [WhatsAppChat]) throws { try choose(chosen, everyChat: false) }

    /// Choosing adds the chats to those WhatsApp may be read for; it never takes another machine's chat away.
    private func choose(_ chosen: [WhatsAppChat], everyChat: Bool) throws {
        try capture.update {
            $0.switches[.whatsapp] = true
            $0.allowList[.whatsapp, default: []].formUnion(chosen.map(\.jid))
        }
        try chatsKey.save(chosen, to: store)
        try everyChatKey.save(everyChat, to: store)
        chats = chosen
        readsEveryChat = everyChat
        keep()
    }

    /// Opens the chooser again over the chats already chosen.
    func change() { isChanging = true }

    /// Closes the chooser and leaves the chosen chats as they are.
    func keep() {
        isChanging = false
        matching = []
        closeDiscovery()
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

    /// Said to the founder before a chat is stopped.
    static let stopReadingWarning = "Workbench erases what it stored from this chat."

    /// The warning, and the machines that stop reading the chat with it.
    static func stopWarning(alsoStopping names: [String]) -> String {
        guard !names.isEmpty else { return stopReadingWarning }
        let list = names.formatted(.list(type: .and, width: .standard))
        return "\(stopReadingWarning) \(list) also \(names.count == 1 ? "stops" : "stop") reading it."
    }

    /// Stops reading one chat for every machine. Consent is per chat and global: the chat leaves the allow-list, which
    /// erases its lines and the copies of their words (`CaptureService.update`), and then each machine that chose it
    /// drops it. Other chats stay.
    static func stopReading(_ chat: WhatsAppChat, among sources: [WhatsAppSource], capture: CaptureService) throws {
        try capture.update { $0.allowList[.whatsapp]?.remove(chat.jid) }
        for source in sources where source.chats.contains(where: { $0.id == chat.id }) { try source.drop(chat) }
    }

    private func drop(_ chat: WhatsAppChat) throws {
        chats.removeAll { $0.id == chat.id }
        try chatsKey.save(chats, to: store)
        let remaining = Set(chats.map(\.jid))
        members = members.filter { $0.chats.map { !remaining.isDisjoint(with: $0) } ?? true }
        try membersKey.save(members, to: store)
    }

    /// The people in the chats as WhatsApp has them now. Reading WhatsApp's data can make macOS ask the founder again
    /// (measured: 7 "access data from other apps" prompts in one day), so only checks that must be live use this.
    func loadMembers() async throws {
        guard !chats.isEmpty else { return }
        try remember(try await reader().people())
    }

    /// The members as of the last read, for showing a page; WhatsApp is read only when none are known yet.
    func showMembers() async throws {
        if members.isEmpty { try await loadMembers() }
    }

    private func switchOn() throws {
        if !capture.policy.isEnabled(.whatsapp) { try capture.update { $0.switches[.whatsapp] = true } }
    }

    private func remember(_ people: WhatsAppPeople) throws {
        members = people.members
        names = people.names
        try membersKey.save(people.members, to: store)
        try loadTeamHandles()
    }

    private func loadTeamHandles() throws {
        let people = Set((try store.queries.team()?.people ?? []).filter { !$0.isMe }.compactMap(\.id))
        teamHandles = Set(try store.queries.whatsappLinks().filter { people.contains($0.key) }.values)
    }

    /// The day's messages of every chosen chat, each a numbered line, and the people in them. The chats are first read
    /// into the evidence store; the lines come from there, as the proof cards read them. A message deleted for everyone
    /// has no words to show a model, so it is not a line here. With several chats each line names its chat.
    func evidence(on day: WorkDay) async throws -> EvidenceSet {
        guard !chats.isEmpty else { return EvidenceSet(lines: []) }
        try await keepChats()
        try await loadMembers()
        let stored = try store.queries.currentLines(in: chats.map(\.container), from: day.start, to: day.end)
        let lines = stored.filter { !$0.isTombstone }.map { evidence($0, start: day.start) }
        return EvidenceSet(
            lines: lines,
            context: ["members": members.map(\.name) + [founderLabel(founder())], "founder": [founderLabel(founder())]])
    }

    /// The lines that prove a fact, as the run that made it saw them, with a deleted message shown as deleted. Reading
    /// them reads no chat.
    func proof(of item: Item, reach: Int) async throws -> [ChatLine] {
        if names.isEmpty { try await loadMembers() }
        return try store.queries.proofLines(of: item, reach: reach).map { proof in
            ChatLine(
                id: proof.line.number, time: proof.line.time, text: words(of: proof.line).line,
                isCited: proof.isCited)
        }
    }

    /// Reads the chosen chats into the store. A chat that cannot be read stops the reading, as it always did.
    private func keepChats() async throws {
        let report = try await store.ingest(reader(), owner: try capture.owner(), now: store.clock())
        if let failure = report.failures.first { throw failure.error }
    }

    private func reader() -> WhatsAppChatReader { reader(chatJIDs: chats.map(\.jid)) }

    private func reader(chatJIDs: [String]) -> WhatsAppChatReader {
        WhatsAppChatReader(
            container: container, chatJIDs: chatJIDs, policy: store, me: founderLabel(founder()), hear: hear)
    }

    private func evidence(_ stored: StoredLine, start: Date) -> Evidence {
        let shown = words(of: stored)
        return Evidence(
            id: stored.number, start: stored.time ?? start, line: shown.line, quotable: shown.quote.map { [$0] } ?? [],
            lineID: stored.lineID, provenance: stored.provenance)
    }

    /// A stored line as one line of text, and the words a quote may be taken from. A deleted message has no words.
    private func words(of stored: StoredLine) -> (line: String, quote: String?) {
        let text = stored.isTombstone ? Self.deletedWords : MemberNames.mentions(in: stored.text, names: names)
        let chat = isSeveral ? chatNames[stored.container].map { "[\($0)] " } ?? "" : ""
        return ("\(chat)\(sender(of: stored)): \(text)", stored.isTombstone ? nil : text)
    }

    static let deletedWords = "This message was deleted"

    private var chatNames: [String: String] {
        Dictionary(chats.map { ($0.container, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    private func sender(of stored: StoredLine) -> String {
        guard let actor = stored.actor else { return "Unknown" }
        if actor == WhatsAppChatReader.audienceOwner { return founderLabel(founder()) }
        return names[actor] ?? MemberNames.fallback(for: actor)
    }
}

func founderLabel(_ name: String) -> String { name.isEmpty ? "You" : "\(name) (You)" }
