import CaptureService
import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

@Suite struct ProposalTests {
    /// A store with the built-in machines and one timeline block on each of `count` training days before today.
    private func store(trainingDays count: Int) async throws -> (Store, Crew, [Int64]) {
        let store = try scratchStore()
        try store.savePolicy(CapturePolicy(switches: [.screen: true]))
        try store.seedMachines(MachineTemplate.seeded.map { ($0.spec, $0.name) })
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "" }, notifier: FakeNotifier())
        let today = WorkDay(containing: store.clock())
        let days = (1...30).map { today.adding(days: -$0) }.filter { EvalSplit($0) == .dev }.prefix(count)
        let model = RecordedModel(ScriptedModel(#"{"items":[]}"#), store: store)
        for day in days {
            let (_, run) = try await model.generate(
                Nothing.self, schema: .object([.init("items", .array(.string))]), task: HelperSpec.timeline.task,
                instructions: "v1", input: "x")
            let block = Item(
                task: HelperSpec.timeline.task, day: day, scope: "", source: .screen, citeFirst: 1, citeLast: 1,
                start: day.start.addingTimeInterval(3600), end: day.start.addingTimeInterval(7200),
                fields: ["task": "Triage inbound decks", "project": "Fund"], quote: "Deck", run: run)
            try store.saveReading(
                .init(items: [block], dropped: 0, run: run), of: .timeline, day: day, scope: "",
                grant: try await store.grant(for: .screen, at: store.clock()))
        }
        let ids = try store.queries.items(of: HelperSpec.timeline.task, since: today.adding(days: -30)).compactMap(\.id)
        return (store, crew, ids)
    }

    private func reply(_ name: String, evidence: [Int64]) -> String {
        #"{"proposals":[{"name":"\#(name)","template":"day.timeline","brief":"List each inbound deck with its sector.","why":"You triage decks every day.","view":"table","evidence":\#(evidence)}]}"#
    }

    @Test func mochiProposesFromTrainingDaysAndBuildingAProposalMakesTheMachine() async throws {
        let (store, crew, ids) = try await store(trainingDays: 3)
        let scripted = ScriptedModel(reply("Deck triage", evidence: ids))
        let mochi = MochiModel(store: store, crew: crew, makeModel: { _ in RecordedModel(scripted, store: store) })
        #expect(mochi.trainingDays == 3 && mochi.canDiscover)
        await mochi.discover()
        #expect(mochi.waiting.map(\.name) == ["Deck triage"])
        let first = try #require(mochi.waiting.first)
        #expect(mochi.evidence(first).count == 3)
        let accepted = try #require(mochi.waiting.first)
        let id = try #require(mochi.accept(accepted))
        let built = try #require(crew.helper(id: id))
        #expect(built.name == "Deck triage")
        #expect(built.spec.brief == "List each inbound deck with its sector.")
        #expect(HelperSpec.timeline.view == .timeline && built.spec.view == .table)
        #expect(scripted.inputs.withLock { $0.first?.contains("Views: table, timeline.") == true })
        #expect(mochi.waiting.isEmpty)
        #expect(mochi.acceptance.accepted == 1 && mochi.acceptance.decided == 1)
    }

    @Test func notNowAndNeverAreRecordedAndCountTowardAcceptanceOnlyWhenFinal() async throws {
        let (store, crew, ids) = try await store(trainingDays: 3)
        let scripted = ScriptedModel(reply("Deck triage", evidence: ids))
        let mochi = MochiModel(store: store, crew: crew, makeModel: { _ in RecordedModel(scripted, store: store) })
        await mochi.discover()
        mochi.decide(try #require(mochi.waiting.first), .later)
        #expect(mochi.waiting.isEmpty && mochi.acceptance.decided == 0)
        await mochi.discover()
        mochi.decide(try #require(mochi.waiting.first), .rejected)
        #expect(mochi.acceptance.decided == 1 && mochi.acceptance.accepted == 0)
        #expect(crew.crew.map(\.name) == ["Pip"])
    }

    @Test func withFewerThanThreeTrainingDaysMochiDoesNotRun() async throws {
        let (store, crew, _) = try await store(trainingDays: 2)
        let scripted = ScriptedModel(#"{"proposals":[]}"#)
        let mochi = MochiModel(store: store, crew: crew, makeModel: { _ in RecordedModel(scripted, store: store) })
        #expect(!mochi.canDiscover)
        await mochi.discover()
        #expect(scripted.inputs.withLock { $0.isEmpty })
    }
}
