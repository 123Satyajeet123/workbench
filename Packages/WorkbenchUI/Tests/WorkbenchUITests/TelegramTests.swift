import CaptureService
import Foundation
import LocalSources
import Synchronization
import TelegramReader
import Testing
import WorkbenchCore

@testable import WorkbenchUI

private final class FakeTelegram: TelegramService, Sendable {
    let people = Mutex<[TelegramMember]>([])
    let history = Mutex<[TelegramMessage]>([])
    let connected = Mutex<[TelegramKeys]>([])

    func connect(_ keys: TelegramKeys, policy: CapturePolicy, onChange: @escaping @Sendable (TelegramLogin) -> Void)
        throws
    {
        try TelegramGate.check(policy)
        connected.withLock { $0.append(keys) }
        onChange(.ready(name: "Kabir"))
    }
    func checkPassword(_ password: String) async throws {}
    func groups() async throws -> [TelegramChat] { [team, family] }
    func members(of chat: Int64) async throws -> [TelegramMember] { people.withLock { $0 } }
    func messages(in chat: Int64, from start: Date, to end: Date) async throws -> [TelegramMessage] {
        history.withLock { $0 }
    }
    func signOut() async throws {}
}

nonisolated private let team = TelegramChat(id: -100_111, title: "Acme team", memberCount: 3)
nonisolated private let family = TelegramChat(id: -100_222, title: "Family", memberCount: 5)
nonisolated private let asha = TelegramMember(id: 1, name: "Asha")
nonisolated private let bharat = TelegramMember(id: 2, name: "Bharat")
nonisolated private let apiHash = "0123456789abcdef0123456789abcdef"

@Suite struct TelegramTests {
    private let noon: Date = {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_790_000_000))!
    }()

    private func makeRelay(reply: String = #"{"items":[]}"#) throws -> (
        HelperModel, Store, CaptureService, ScriptedModel, TelegramSource, FakeTelegram
    ) {
        let now = noon
        let store = try scratchStore(clock: { now })
        let capture = try CaptureService(store: store)
        let service = FakeTelegram()
        service.people.withLock { $0 = [asha, bharat] }
        let account = TelegramAccount(service: service, capture: capture, secrets: MemorySecrets())
        let source = try TelegramSource(
            store: store, capture: capture, account: account, task: HelperSpec.teamTelegram.task,
            founder: { "Kabir" })
        let model = ScriptedModel(reply)
        let relay = HelperModel(
            machine: .test(.teamTelegram, "Relay"), source: source, store: store,
            makeModel: { _ in RecordedModel(model, store: store) })
        return (relay, store, capture, model, source, service)
    }

    private func connected(_ source: TelegramSource) async throws {
        try source.account.connect(apiID: "12345", apiHash: apiHash)
        for _ in 0..<50 where !source.account.isReady { try await Task.sleep(for: .milliseconds(20)) }
    }

    @Test func keysThatAreNotAnIDAndAHashAreRefusedAndGoodOnesSwitchTelegramOn() async throws {
        let (_, _, capture, _, source, service) = try makeRelay()
        #expect(throws: TelegramFailure.self) { try source.account.connect(apiID: "abc", apiHash: apiHash) }
        #expect(throws: TelegramFailure.self) { try source.account.connect(apiID: "12345", apiHash: "short") }
        #expect(service.connected.withLock { $0.isEmpty } && !capture.policy.isEnabled(.telegram))
        try await connected(source)
        #expect(source.account.isReady && capture.policy.isEnabled(.telegram))
        let keys = try #require(service.connected.withLock { $0.first })
        #expect(keys.apiID == 12345 && keys.apiHash == apiHash && keys.databaseKey.count == 32)
    }

    @Test func aGroupIsReadOnlyAfterYouConfirmEveryoneInItAgreed() async throws {
        let (relay, store, capture, _, source, _) = try makeRelay()
        try await connected(source)
        try await source.loadGroups()
        try await source.ask(team)
        #expect(source.askingPeople == [asha, bharat])
        #expect(!relay.isReady && capture.policy.allowList[.telegram, default: []].isEmpty)

        try source.confirmEveryoneAgreed()
        #expect(relay.isReady && source.asking == nil && !source.isChanging)
        #expect(capture.policy.allowList[.telegram] == [team.label])
        #expect(capture.policy.authorize(CaptureRequest(kind: .telegram, label: family.label), at: noon).grant == nil)
        let reopened = try TelegramSource(
            store: store, capture: capture, account: source.account, task: HelperSpec.teamTelegram.task,
            founder: { "Kabir" })
        #expect(reopened.chat == team && reopened.consent?.people == [asha, bharat] && reopened.isReady)
    }

    @Test func readingADaySendsTheGroupsLinesAndKeepsTheFacts() async throws {
        let reply = #"""
            {"items":[{"person":"Asha","project":"Login","kind":"done","text":"Login API","eta":"","asks":"team","stance":"said","cite":11,"quote":"login API done"}],"closes":[]}
            """#
        let (relay, _, _, model, source, service) = try makeRelay(reply: reply)
        try await connected(source)
        try await source.ask(team)
        try source.confirmEveryoneAgreed()
        service.history.withLock {
            $0 = [
                TelegramMessage(
                    id: 10, chat: team.id, date: noon.addingTimeInterval(-60), kind: .text, sender: "Kabir",
                    isOutgoing: true, text: "ki aaj kya kiya?"),
                TelegramMessage(
                    id: 11, chat: team.id, date: noon, kind: .text, sender: "Asha", isOutgoing: false,
                    text: "login API done"),
                TelegramMessage(
                    id: 12, chat: team.id, date: noon, kind: .document, sender: "Bharat", isOutgoing: false, text: "",
                    title: "spec.pdf"),
            ]
        }
        await relay.read()

        let input = try #require(model.inputs.withLock { $0.first })
        #expect(input.contains("Kabir (founder): ki aaj kya kiya?"))
        #expect(input.contains("Asha: login API done") && input.contains("Bharat: spec.pdf"))
        #expect(relay.items.map(\.quote) == ["login API done"])
        #expect(relay.items.map(\.source) == [.telegram])
    }

    @Test func someoneNewInTheGroupStopsTheReadUntilYouAskAgain() async throws {
        let (relay, _, _, model, source, service) = try makeRelay()
        try await connected(source)
        try await source.ask(team)
        try source.confirmEveryoneAgreed()
        let chitra = TelegramMember(id: 3, name: "Chitra")
        service.people.withLock { $0.append(chitra) }
        await relay.read()
        #expect(model.inputs.withLock { $0.isEmpty })
        #expect(relay.problem?.contains("Chitra") == true)

        try await source.askAgain()
        #expect(relay.isChoosingSource && source.askingPeople.contains(chitra))
        try source.confirmEveryoneAgreed()
        #expect(source.consent?.people.contains(chitra) == true && !relay.isChoosingSource)
    }

    @Test func stoppingForgetsTheGroupAndTakesBackItsPermission() async throws {
        let (relay, store, capture, _, source, _) = try makeRelay()
        try await connected(source)
        try await source.ask(team)
        try source.confirmEveryoneAgreed()
        try source.stopReading()
        #expect(!relay.isReady && capture.policy.allowList[.telegram, default: []].isEmpty)
        let reopened = try TelegramSource(
            store: store, capture: capture, account: source.account, task: HelperSpec.teamTelegram.task,
            founder: { "Kabir" })
        #expect(reopened.chat == nil && reopened.consent == nil)
    }
}
