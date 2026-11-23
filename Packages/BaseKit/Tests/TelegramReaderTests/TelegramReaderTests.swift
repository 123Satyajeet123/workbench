import Foundation
import Kernel
import LocalSources
import Testing
import WorkbenchCore

@testable import TelegramReader

private final class Recorded: TelegramService, @unchecked Sendable {
    var people: [TelegramMember] = []
    var history: [TelegramMessage] = []
    private(set) var asked: [Int64] = []
    private(set) var tags: [String] = []

    func connect(_ keys: TelegramKeys, policy: CapturePolicy, onChange: @escaping @Sendable (TelegramLogin) -> Void)
        throws
    {}
    func checkPassword(_ password: String) async throws {}
    func groups() async throws -> [TelegramChat] { [] }
    func members(of chat: Int64) async throws -> [TelegramMember] { people }
    func messages(in chat: Int64, from start: Date, to end: Date, me: String) async throws -> [TelegramMessage] {
        asked.append(chat)
        tags.append(me)
        return history
    }
    func signOut() async throws {}
    func disconnect() {}
}

private let group: Int64 = -100_123
private let start = Date(timeIntervalSince1970: 1_800_000_000)
private let end = start.addingTimeInterval(86_400)
private let asha = TelegramMember(id: 1, name: "Asha")
private let ravi = TelegramMember(id: 2, name: "Ravi")
private func owner() throws -> PersonID { try PersonID("test-owner") }

private func message(_ id: Int64, at offset: TimeInterval, chat: Int64 = group) -> TelegramMessage {
    TelegramMessage(
        id: id, chat: chat, date: start.addingTimeInterval(offset), kind: .text, sender: "Asha", senderID: 1,
        isOutgoing: false, text: "line \(id)")
}

private func storeAllowing(_ chats: [Int64], switchedOn: Bool = true) throws -> Store {
    let store = try Store(directory: FileManager.default.temporaryDirectory.appending(path: "tg-\(UUID().uuidString)"))
    try store.savePolicy(
        CapturePolicy(switches: [.telegram: switchedOn], allowList: [.telegram: Set(chats.map(String.init))]))
    return store
}

private func confirm(_ people: [TelegramMember], in store: Store) throws {
    let audience = try #require(TelegramChatReader.audience(of: people, chat: group))
    try store.agree(audience: audience, kind: .telegram, label: String(group))
}

@Suite struct TelegramReaderTests {
    @Test func aChosenGroupWhoseMembersAllAgreedGivesThatDaysMessagesInOrder() async throws {
        let service = Recorded()
        service.people = [asha, ravi]
        service.history = [message(3, at: 500), message(1, at: -10), message(2, at: 100), message(4, at: 86_400)]
        service.history.append(message(5, at: 200, chat: -100_999))
        let store = try storeAllowing([group])
        try confirm([asha, ravi], in: store)
        let reader = TelegramChatReader(
            service: service, chat: group, agreed: [1, 2], policy: store, me: "Kabir (You)", window: start..<end)
        let report = try await store.ingest(reader, owner: try owner(), now: start)
        #expect(report.failures.isEmpty && report.inserted == 2)
        let lines = try store.queries.currentLines(in: [String(group)], from: start, to: end)
        #expect(lines.map(\.text) == ["line 2", "line 3"])
        #expect(service.tags == ["Kabir (You)"])
    }

    @Test func aNewcomerWhoHasNotAgreedStopsTheReadBeforeAnyMessageIsFetched() async throws {
        let service = Recorded()
        service.people = [asha, ravi]
        service.history = [message(1, at: 10)]
        let store = try storeAllowing([group])
        try confirm([asha], in: store)
        let reader = TelegramChatReader(service: service, chat: group, agreed: [1], policy: store, window: start..<end)
        let report = try await store.ingest(reader, owner: try owner(), now: start)
        #expect(report.failures.first?.error as? TelegramConsentMissing == TelegramConsentMissing(people: [ravi]))
        #expect(service.asked.isEmpty)
    }

    @Test func aWriteForAnAudienceNobodyConfirmedIsRefusedInsideTheTransaction() async throws {
        let service = Recorded()
        service.people = [asha, ravi]
        service.history = [message(1, at: 10)]
        let store = try storeAllowing([group])
        try confirm([asha], in: store)
        let reader = TelegramChatReader(
            service: service, chat: group, agreed: [1, 2], policy: store, window: start..<end)
        let report = try await store.ingest(reader, owner: try owner(), now: start)
        #expect(report.failures.first?.error as? EvidenceError == .audienceNotAgreed)
        #expect(try store.queries.currentLines(in: [String(group)], from: start, to: end).isEmpty)
    }

    @Test func takingTheGroupOffTheListErasesItsLinesAndItsConfirmation() async throws {
        let service = Recorded()
        service.people = [asha]
        service.history = [message(1, at: 10)]
        let store = try storeAllowing([group])
        try confirm([asha], in: store)
        let reader = TelegramChatReader(service: service, chat: group, agreed: [1], policy: store, window: start..<end)
        _ = try await store.ingest(reader, owner: try owner(), now: start)
        try store.eraseEvidence(.grant(kind: .telegram, label: String(group)))
        #expect(try store.queries.currentLines(in: [String(group)], from: start, to: end).isEmpty)
        let again = try await store.ingest(reader, owner: try owner(), now: start)
        #expect(again.failures.first?.error as? EvidenceError == .audienceNotAgreed)
    }

    @Test func aGroupThatIsNotChosenOrATelegramSwitchedOffIsNeverRead() async throws {
        let service = Recorded()
        service.people = [asha]
        let store = try storeAllowing([group])
        let other = TelegramChatReader(service: service, chat: -100_999, agreed: [1], policy: store)
        let notChosen = try await store.ingest(other, owner: try owner(), now: start)
        #expect(notChosen.failures.first?.error as? ReadError == .denied(.labelNotAllowed))
        let off = try storeAllowing([group], switchedOn: false)
        let switchedOff = TelegramChatReader(service: service, chat: group, agreed: [1], policy: off)
        let report = try await off.ingest(switchedOff, owner: try owner(), now: start)
        #expect(report.failures.first?.error as? ReadError == .denied(.sourceSwitchedOff))
        #expect(service.asked.isEmpty)
    }

    @Test func workbenchConnectsOnlyWithTelegramSwitchedOnAndCaptureOn() throws {
        #expect(throws: ReadError.denied(.sourceSwitchedOff)) { try TelegramGate.check(CapturePolicy()) }
        #expect(throws: ReadError.denied(.captureOff)) {
            try TelegramGate.check(CapturePolicy(mode: .off, switches: [.telegram: true]))
        }
        try TelegramGate.check(CapturePolicy(switches: [.telegram: true]))
    }
}
