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

    func evidence(on day: WorkDay) throws -> EvidenceSet {
        EvidenceSet(lines: try sessions(on: day).map(\.evidence))
    }
}

/// One WhatsApp group the founder chose. Choosing it is the consent: this chat, and no other, may be read.
@Observable
final class WhatsAppSource {
    private(set) var chat: WhatsAppChat?
    private(set) var groups: [WhatsAppChat] = []
    private(set) var members: [WhatsAppMember] = []

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let capture: CaptureService
    @ObservationIgnored private let founder: () -> String
    @ObservationIgnored private let container: URL
    @ObservationIgnored private let chatKey: String

    init(
        store: Store, capture: CaptureService, task: String, founder: @escaping () -> String,
        container: URL = WhatsAppChatReader.defaultContainer
    ) throws {
        self.store = store
        self.capture = capture
        self.founder = founder
        self.container = container
        chatKey = "\(task).chat"
        chat = try store.queries.state(forKey: chatKey).map {
            try JSONDecoder().decode(WhatsAppChat.self, from: Data($0.utf8))
        }
    }

    /// Group names to choose from. Listing names needs the WhatsApp switch on; no chat is readable until one is chosen.
    func loadGroups() throws {
        if !capture.policy.isEnabled(.whatsapp) { try capture.update { $0.switches[.whatsapp] = true } }
        groups = try WhatsAppChatReader.groups(container: container, policy: capture.policy)
    }

    func choose(_ group: WhatsAppChat) throws {
        try capture.update {
            $0.switches[.whatsapp] = true
            $0.allowList[.whatsapp] = [group.jid]
        }
        try store.saveState(String(decoding: try JSONEncoder().encode(group), as: UTF8.self), forKey: chatKey)
        chat = group
        groups = []
    }

    func loadMembers() async throws {
        guard let chat else { return }
        members = try await reader(chat).members()
    }

    /// The day's messages, each a numbered line, and the group's members.
    func evidence(on day: WorkDay) async throws -> EvidenceSet {
        guard let chat else { return EvidenceSet(lines: []) }
        let reader = reader(chat)
        members = try await reader.members()
        let lines = try await reader.entries(from: day.start, to: day.end).compactMap(line)
        return EvidenceSet(lines: lines, context: ["members": members.map(\.name)])
    }

    private func reader(_ chat: WhatsAppChat) -> WhatsAppChatReader {
        WhatsAppChatReader(container: container, chatJID: chat.jid, policy: store)
    }

    private func line(_ entry: WhatsAppEntry) -> Evidence? {
        let text = [entry.title, entry.text].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
        guard !text.isEmpty else { return nil }
        let sender: String
        switch entry.sender {
        case .me: sender = founder().isEmpty ? "Founder" : "\(founder()) (founder)"
        case .member(_, let name): sender = name
        }
        return Evidence(id: entry.id, start: entry.date, line: "\(sender): \(text)", quotable: [text])
    }
}
