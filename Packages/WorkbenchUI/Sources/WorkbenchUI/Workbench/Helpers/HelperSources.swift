import CaptureService
import Foundation
import LocalSources
import Observation
import WorkbenchCore

/// The founder's screen sessions, from the activity the capture service kept.
struct ScreenSource {
    /// Activity this long before the day starts tells which window was open at its start.
    private static let lookBack: TimeInterval = 6 * 3600

    let store: Store

    func sessions(on day: WorkDay) throws -> [ScreenSession] {
        let activity = try store.queries.activities(from: day.start.addingTimeInterval(-Self.lookBack), to: day.end)
        return Sessions.make(from: activity, start: day.start, end: min(day.end, store.clock()))
    }

    /// The window in front now is still growing: it waits until it closes, so a block never stops mid-task and a
    /// later reading never finds its line already read.
    static let stillOpen: TimeInterval = 60

    func evidence(on day: WorkDay) throws -> EvidenceSet {
        var sessions = try sessions(on: day)
        if let last = sessions.last, store.clock().timeIntervalSince(last.end) < Self.stillOpen {
            sessions.removeLast()
        }
        return EvidenceSet(lines: sessions.map(\.evidence))
    }
}

/// Pages the founder saw on the sites a machine's owner named. Naming the sites is the consent: no other site's text
/// is read. The text comes from the browser extension, kept only under the Screen text switch.
@Observable
final class PageSource {
    private(set) var sites: [String]

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let sitesKey: String

    init(store: Store, task: String) throws {
        self.store = store
        sitesKey = "\(task).sites"
        sites =
            try store.queries.state(forKey: sitesKey).map {
                try JSONDecoder().decode([String].self, from: Data($0.utf8))
            }
            ?? []
    }

    /// Sites as the founder typed them, separated by commas or spaces. Anything that is not a site is left out.
    func choose(_ typed: String) throws {
        let chosen = Array(
            Set(typed.split(whereSeparator: { $0 == "," || $0.isWhitespace }).compactMap { WebPage.site(String($0)) })
        ).sorted()
        try store.saveState(String(decoding: try JSONEncoder().encode(chosen), as: UTF8.self), forKey: sitesKey)
        sites = chosen
    }

    func reading(on day: WorkDay) throws -> (pages: [Activity], leftOut: Int) {
        WebPage.reading(try store.queries.activities(from: day.start, to: day.end), sites: sites)
    }

    func evidence(on day: WorkDay) throws -> EvidenceSet {
        EvidenceSet(lines: try reading(on: day).pages.compactMap(\.pageEvidence))
    }
}

/// The WhatsApp chats a machine reads: one group the founder chose, or several chats chosen by a rule (groups whose
/// name holds some words, and direct chats with their members). Choosing is the consent: these chats, and no other,
/// may be read.
@Observable
final class WhatsAppSource {
    private(set) var chats: [WhatsAppChat] = []
    private(set) var groups: [WhatsAppChat] = []
    /// The chats a rule would choose, shown before the founder confirms.
    private(set) var matching: [WhatsAppChat] = []
    private(set) var members: [WhatsAppMember] = []

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let capture: CaptureService
    @ObservationIgnored private let founder: () -> String
    @ObservationIgnored private let container: URL
    @ObservationIgnored private let chatsKey: String
    @ObservationIgnored private let membersKey: String

    init(
        store: Store, capture: CaptureService, task: String, founder: @escaping () -> String,
        container: URL = WhatsAppChatReader.defaultContainer
    ) throws {
        self.store = store
        self.capture = capture
        self.founder = founder
        self.container = container
        chatsKey = "\(task).chats"
        membersKey = "\(task).members"
        chats =
            try store.queries.state(forKey: chatsKey).map {
                try JSONDecoder().decode([WhatsAppChat].self, from: Data($0.utf8))
            } ?? []
        members =
            try store.queries.state(forKey: membersKey).map {
                try JSONDecoder().decode([WhatsAppMember].self, from: Data($0.utf8))
            } ?? []
    }

    /// The one chosen group, for a machine that reads one.
    var chat: WhatsAppChat? { chats.count == 1 ? chats.first : nil }
    var isSeveral: Bool { chats.count > 1 }

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
        try store.saveState(String(decoding: try JSONEncoder().encode(chosen), as: UTF8.self), forKey: chatsKey)
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
        try store.saveState(String(decoding: try JSONEncoder().encode(current), as: UTF8.self), forKey: membersKey)
    }

    /// The day's messages of every chosen chat, each a numbered line, and the people in them, from one read. With
    /// several chats each line names its chat.
    func evidence(on day: WorkDay) async throws -> EvidenceSet {
        guard !chats.isEmpty else { return EvidenceSet(lines: []) }
        let (entries, people) = try await reader().read(from: day.start, to: day.end)
        try remember(people)
        let names = Dictionary(chats.map { ($0.jid, $0.name) }, uniquingKeysWith: { first, _ in first })
        let lines = entries.compactMap { entry in
            line(entry).map { line in
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
    private func line(_ entry: WhatsAppEntry) -> Evidence? {
        var parts = [entry.title, entry.text].compactMap { $0 }.filter { !$0.isEmpty }
        if entry.kind == .photo, case .file(let url) = entry.media {
            let seen = ImageText.recognize(url)
            if !seen.isEmpty { parts.insert("[photo] \(seen)", at: 0) }
        }
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
