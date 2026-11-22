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
    private(set) var groups: [WhatsAppChat] = []
    /// The chats a rule would choose, shown before the founder confirms.
    private(set) var matching: [WhatsAppChat] = []
    private(set) var members: [WhatsAppMember] = []
    /// The WhatsApp IDs of the teammates the founder set up and linked, as of the last read.
    private(set) var teamHandles: Set<String> = []

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let capture: CaptureService
    @ObservationIgnored private let founder: () -> String
    @ObservationIgnored private let container: URL
    @ObservationIgnored private let chatsKey: StateKey<[WhatsAppChat]>
    @ObservationIgnored private let membersKey: StateKey<[WhatsAppMember]>

    init(
        store: Store, capture: CaptureService, task: String, founder: @escaping () -> String,
        container: URL = WhatsAppChatReader.defaultContainer
    ) throws {
        self.store = store
        self.capture = capture
        self.founder = founder
        self.container = container
        chatsKey = MachineKey.chats(task)
        membersKey = MachineKey.members(task)
        chats = try chatsKey.load(from: store) ?? []
        members = try membersKey.load(from: store) ?? []
        try loadTeamHandles()
    }

    /// The one chosen group, for a machine that reads one.
    var chat: WhatsAppChat? { chats.count == 1 ? chats.first : nil }
    var isSeveral: Bool { chats.count > 1 }

    /// One chat is the machine's scope; several chats are one scope for the machine.
    var scope: String { chat?.jid ?? "" }
    var isReady: Bool { !chats.isEmpty }
    /// The people the founder expects to hear from. One chat: everyone in it. Several chats: the teammates the
    /// founder set up in Team setup, when any is linked to a WhatsApp ID; else the people in the first chosen group.
    var expectedPeople: [WhatsAppMember] {
        guard isSeveral else { return members }
        let team = members.filter { teamHandles.contains($0.jid) }
        guard team.isEmpty else { return team }
        guard let first = chats.first(where: \.isGroup) ?? chats.first else { return [] }
        return members.filter { $0.chats?.contains(first.jid) == true }
    }

    var context: [String: [String]] { ["members": expectedPeople.map(\.name)] }
    /// With several chats, each one of them must be allowed.
    var grantLabels: [String?] { isSeveral ? chats.map(\.jid) : [scope.isEmpty ? nil : scope] }

    /// Group names to choose from. Listing names needs the WhatsApp switch on; no chat is readable until one is chosen.
    func loadGroups() throws {
        try switchOn()
        groups = try WhatsAppChatReader.groups(container: container, policy: capture.policy)
    }

    /// The chats a rule chooses, to show before the founder confirms.
    func preview(_ selection: ChatSelection) throws {
        try switchOn()
        matching = try WhatsAppChatReader.chats(matching: selection, container: container, policy: capture.policy)
    }

    func choose(_ group: WhatsAppChat) throws { try choose([group]) }

    /// Choosing adds the chats to those WhatsApp may be read for; it never takes another machine's chat away.
    func choose(_ chosen: [WhatsAppChat]) throws {
        try capture.update {
            $0.switches[.whatsapp] = true
            $0.allowList[.whatsapp, default: []].formUnion(chosen.map(\.jid))
        }
        try chatsKey.save(chosen, to: store)
        chats = chosen
        groups = []
        matching = []
    }

    /// The people in the chats as WhatsApp has them now. Reading WhatsApp's data can make macOS ask the founder again
    /// (measured: 7 "access data from other apps" prompts in one day), so only checks that must be live use this.
    func loadMembers() async throws {
        guard !chats.isEmpty else { return }
        try remember(try await reader().members())
    }

    /// The members as of the last read, for showing a page; WhatsApp is read only when none are known yet.
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

    /// The day's messages of every chosen chat, each a numbered line, and the people in them, from one read. With
    /// several chats each line names its chat.
    func evidence(on day: WorkDay) async throws -> EvidenceSet {
        guard !chats.isEmpty else { return EvidenceSet(lines: []) }
        let (entries, people) = try await reader().read(from: day.start, to: day.end)
        try remember(people)
        let photos = await ImageText.texts(in: entries.compactMap(\.photo))
        let names = Dictionary(chats.map { ($0.jid, $0.name) }, uniquingKeysWith: { first, _ in first })
        let lines = entries.compactMap { entry in
            line(entry, photos: photos).map { line in
                guard isSeveral, let chat = names[entry.chat] else { return line }
                var named = line
                named.line = "[\(chat)] " + line.line
                return named
            }
        }
        return EvidenceSet(lines: lines, context: ["members": members.map(\.name)])
    }

    private func reader() -> WhatsAppChatReader {
        WhatsAppChatReader(container: container, chatJIDs: chats.map(\.jid), policy: store)
    }

    /// A message as one numbered line. A photo's line is the text in it, read on this Mac, and its caption.
    private func line(_ entry: WhatsAppEntry, photos: [URL: String]) -> Evidence? {
        var parts = [entry.title, entry.text].compactMap { $0 }.filter { !$0.isEmpty }
        if let url = entry.photo, let seen = photos[url], !seen.isEmpty { parts.insert("[photo] \(seen)", at: 0) }
        let text = parts.joined(separator: " — ")
        guard !text.isEmpty else { return nil }
        let sender: String
        switch entry.sender {
        case .me: sender = founder().isEmpty ? "Founder" : "\(founder()) (founder)"
        case .member(_, let name): sender = name
        }
        return Evidence(id: entry.id, start: entry.date, line: "\(sender): \(text)", quotable: [text])
    }
}

extension WhatsAppEntry {
    fileprivate var photo: URL? {
        guard kind == .photo, case .file(let url) = media else { return nil }
        return url
    }
}
