import CaptureService
import Foundation
import Synchronization
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// Pip as the fact machine: typed facts with a project that stays the same across readings, opened and closed over days.
@Suite struct FactMachineTests {
    private let noon: Date = {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_790_000_000))!
    }()

    @Test func theSecondReadingIsShownTheProjectsItUsedAndAFactWithNoProjectIsDropped() async throws {
        let now = noon
        let store = try scratchStore(clock: { now })
        let container = try whatsApp(at: noon)
        let source = try WhatsAppSource(
            store: store, capture: try CaptureService(store: store), task: "team.ledger-1", founder: { "Kabir" },
            container: container)
        try source.loadGroups()
        try source.choose(try #require(source.groups.first { $0.jid == teamJID }))
        let model = KeyedModel([
            "You keep the facts of a founder's company":
                #"{"items":[{"kind":"status","text":"Login API is done","person":"Asha","project":"Login API","eta":"","asks":"team","stance":"said","cite":@login API done@,"quote":"login API done"},{"kind":"question","text":"No project","person":"Asha","project":" ","eta":"","asks":"team","stance":"said","cite":@login API done@,"quote":"login API done"}],"closes":[]}"#
        ])
        var spec = HelperSpec.team
        spec.task = "team.ledger-1"
        let pip = HelperModel(
            machine: Machine(id: 1, name: "Pip", template: HelperSpec.team.task, spec: spec, state: .active),
            source: source, store: store, makeModel: { _ in RecordedModel(model, store: store) },
            notifier: FakeNotifier())
        await pip.read()
        #expect(pip.items.map { $0["project"] } == ["Login API"])
        #expect(pip.phase == .read(kept: 1, dropped: 1), "a fact needs a project")

        try addMessage(30, "payments blocked on keys", at: noon.addingTimeInterval(600), to: container)
        model.replies.withLock {
            $0["You keep the facts of a founder's company"] =
                #"{"items":[{"kind":"status","text":"Payments are blocked on keys","person":"Asha","project":"Login API","eta":"","asks":"team","stance":"said","cite":@payments blocked on keys@,"quote":"payments blocked on keys"}],"closes":[]}"#
        }
        await pip.read()
        let input = try #require(model.inputs.withLock { $0.last })
        #expect(input.contains("Topics: Login API"), "the project it used before is offered for reuse")
        #expect(pip.items.map(\.quote) == ["login API done", "payments blocked on keys"])
    }

    @Test func aCommitmentFromYesterdayStaysOpenUntilALineTodayClosesIt() async throws {
        let clock = Mutex(noon)
        let store = try scratchStore(clock: { clock.withLock { $0 } })
        let container = try whatsApp(at: noon)
        let source = try WhatsAppSource(
            store: store, capture: try CaptureService(store: store), task: "team.ledger-1", founder: { "Kabir" },
            container: container)
        try source.loadGroups()
        try source.choose(try #require(source.groups.first { $0.jid == teamJID }))
        let model = KeyedModel([
            "You keep the facts of a founder's company":
                #"{"items":[{"kind":"commitment","text":"Ship the login API","person":"Asha","project":"Login API","eta":"","asks":"team","stance":"said","cite":@login API done@,"quote":"login API done"}],"closes":[]}"#
        ])
        var spec = HelperSpec.team
        spec.task = "team.ledger-1"
        let pip = HelperModel(
            machine: Machine(id: 1, name: "Pip", template: HelperSpec.team.task, spec: spec, state: .active),
            source: source, store: store, makeModel: { _ in RecordedModel(model, store: store) },
            notifier: FakeNotifier())
        await pip.read()
        #expect(pip.open.map { $0["text"] } == ["Ship the login API"])

        let tomorrow = noon.addingTimeInterval(86_400)
        clock.withLock { $0 = tomorrow }
        try addMessage(40, "login shipped to everyone", at: tomorrow, to: container)
        model.replies.withLock {
            $0["You keep the facts of a founder's company"] =
                #"{"items":[],"closes":[{"handle":"F1","outcome":"kept","cite":@login shipped to everyone@,"quote":"login shipped"}]}"#
        }
        pip.show(WorkDay(containing: tomorrow))
        await pip.read()
        let input = try #require(model.inputs.withLock { $0.last })
        #expect(input.contains("F1 ("), "yesterday's open commitment is shown by handle")
        #expect(pip.open.isEmpty)
        #expect(pip.closed.map { $0.closed?.outcome } == ["kept"])

        pip.reopen(try #require(pip.closed.first))
        #expect(pip.open.count == 1 && pip.closed.isEmpty, "the founder can undo a wrong close")
    }

    @Test func itemsPipMadeBeforeTheFactMachineStillShowGroupByPersonAndOpenPlansAndBlockers() async throws {
        let now = noon
        let store = try scratchStore(clock: { now })
        let container = try whatsApp(at: noon)
        let source = try WhatsAppSource(
            store: store, capture: try CaptureService(store: store), task: HelperSpec.team.task, founder: { "Kabir" },
            container: container)
        try source.loadGroups()
        try source.choose(try #require(source.groups.first { $0.jid == teamJID }))
        let (_, run) = try await RecordedModel(ScriptedModel(#"{"items":[]}"#), store: store).generate(
            Nothing.self, schema: .object([.init("items", .array(.string))]), task: HelperSpec.team.task,
            instructions: "v1", input: "x", holding: [])
        func old(_ person: String, _ kind: String, _ text: String) -> Item {
            Item(
                task: HelperSpec.team.task, day: WorkDay(containing: now), scope: teamJID, source: .whatsapp,
                citeFirst: 11, citeLast: 11, start: now, end: now,
                fields: ["person": person, "kind": kind, "text": text, "eta": ""], quote: "login API done", run: run)
        }
        let grant = try await store.grant(for: .whatsapp, label: teamJID, at: now)
        try store.saveReading(
            .init(
                items: [
                    old("Asha", "done", "Login API"), old("Asha", "plan", "Payments"), old("Bharat", "blocker", "Keys"),
                ],
                dropped: 0, run: run),
            of: .team, day: WorkDay(containing: now), scope: teamJID, grant: grant)
        let pip = HelperModel(
            machine: .test(.team, "Pip"), source: source, store: store, notifier: FakeNotifier())

        #expect(pip.items.count == 3)
        #expect(pip.items.allSatisfy { $0["project"].isEmpty && $0["stance"].isEmpty })
        #expect(
            ItemBoard.groups(of: pip.items, field: "person", expected: pip.context["members"] ?? []) == [
                "Asha", "Bharat",
            ])
        #expect(pip.open.map { $0["text"] }.sorted() == ["Keys", "Payments"], "an old plan and blocker are open facts")
    }
}
