import CaptureService
import Foundation
import Synchronization
import Testing
import WorkbenchCore

@testable import WorkbenchUI

private final class SummaryModel: StructuredModel, Sendable {
    struct Refused: Error {}

    let name = "scripted"
    let calls = Mutex(0)
    let fails: Bool

    init(fails: Bool = false) { self.fails = fails }

    var callCount: Int { calls.withLock { $0 } }

    func generate<T: Decodable & Sendable>(_ type: T.Type, schema: JSONSchema, instructions: String, input: String)
        async throws -> ModelAnswer<T>
    {
        calls.withLock { $0 += 1 }
        if fails { throw Refused() }
        let reply = input.contains("person: ") ? TodaySample.peopleReply : TodaySample.projectsReply
        return ModelAnswer(
            value: try JSONDecoder().decode(T.self, from: Data(reply.utf8)), model: "scripted-1", usage: Usage(),
            reply: reply)
    }
}

@Suite struct TodaySummariesTests {
    private struct Setup {
        let crew: Crew
        let model: TodayModel
        let summarizer: SummaryModel
        var pip: HelperModel { crew.machines.first { $0.spec.task == HelperSpec.team.task }! }
    }

    private func setup(sample: Bool = true, withSummaries: Bool = false, fails: Bool = false) async throws -> Setup {
        let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now)!
        let clock = TestClock(noon)
        let store = try scratchStore(clock: { clock.now })
        try store.seedMachines(MachineTemplate.seeded.map { ($0.spec, $0.name) })
        let summarizer = SummaryModel(fails: fails)
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "Kabir" },
            makeModel: { _ in RecordedModel(summarizer, store: store) }, notifier: FakeNotifier())
        if sample { try await TodaySample.populate(store: store, crew: crew, withSummaries: withSummaries) }
        return Setup(crew: crew, model: TodayModel(store: store, crew: crew), summarizer: summarizer)
    }

    @Test func factsWithoutSummariesAreListedPerPersonAndTodayIsNotEmpty() async throws {
        let day = try await setup()
        #expect(day.model.team.isEmpty && day.model.projects.isEmpty)
        #expect(day.model.unsummarized.map(\.name) == ["Asha", "Meera", "Raj"])
        #expect(!day.model.isEmpty)
    }

    @Test func factsThatNeedNothingAndHaveNoSummaryStillKeepTodayFromBeingEmpty() async throws {
        let day = try await setup()
        day.model.perform(.done, on: day.model.lines.map(\.item), text: "Done")
        #expect(day.model.lines.isEmpty && day.model.team.isEmpty && day.model.projects.isEmpty)
        #expect(!day.model.isEmpty, "the day has facts, so it never says it has nothing")
    }

    @Test func aDayWithNoFactsAtAllIsEmpty() async throws {
        let day = try await setup(sample: false)
        #expect(day.model.isEmpty && day.model.unsummarized.isEmpty)
    }

    @Test func openingTodayWritesTheMissingSummariesInOneCallPerField() async throws {
        let day = try await setup()
        await day.model.summarizeIfMissing()
        #expect(day.summarizer.callCount == 2, "people and projects")
        #expect(day.model.team.map(\.subject) == ["Asha", "Meera", "Raj"])
        #expect(day.model.unsummarized.isEmpty && !day.model.isEmpty && !day.model.isSummarizing)
    }

    @Test func summariesThatAreCurrentAskNoModel() async throws {
        let day = try await setup(withSummaries: true)
        await day.model.summarizeIfMissing()
        #expect(day.summarizer.callCount == 0)
        #expect(day.model.team.count == 3)
    }

    @Test func aDayWithNoFactsAsksNoModel() async throws {
        let day = try await setup(sample: false)
        await day.model.summarizeIfMissing()
        #expect(day.summarizer.callCount == 0)
    }

    @Test func aPausedMachineIsNotSummarized() async throws {
        let day = try await setup()
        day.crew.setPaused(day.pip, true)
        await day.model.summarizeIfMissing()
        #expect(day.summarizer.callCount == 0 && day.model.team.isEmpty)
    }

    @Test func aFailedSummaryKeepsTheFactsListedSaysSoAndIsNotRetriedAtOnce() async throws {
        let day = try await setup(fails: true)
        await day.model.summarizeIfMissing()
        let calls = day.summarizer.callCount
        #expect(calls >= 1 && day.model.problem != nil)
        #expect(!day.model.isEmpty && day.model.unsummarized.count == 3 && day.model.team.isEmpty)
        await day.model.summarizeIfMissing()
        #expect(day.summarizer.callCount == calls, "one try for each day")
    }
}

@Suite struct TodayOldDesignTests {
    @Test func aFactMachineWithNoLifecycleStillFillsTodayWithItsFacts() async throws {
        let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now)!
        let store = try scratchStore(clock: { noon })
        try store.savePolicy(CapturePolicy(switches: [.whatsapp: true], allowList: [.whatsapp: ["team"]]))
        var old = HelperSpec.team
        old.fields =
            old.fields.filter { ["person", "kind", "text"].contains($0.name) } + [
                .init("eta", .text(required: false), meaning: "m")
            ]
        old.lifecycle = nil
        try store.seedMachines([(old, "Pip")])
        let today = WorkDay(containing: noon)
        let (_, run) = try await RecordedModel(ScriptedModel(#"{}"#), store: store).generate(
            Nothing.self, schema: .object([]), task: old.task, instructions: "v1", input: "x", holding: [])
        let fact = Item(
            task: old.task, day: today, scope: "", source: .whatsapp, citeFirst: 5, citeLast: 5, start: noon, end: noon,
            fields: ["person": "Asha", "kind": "plan", "text": "Ship the login API", "eta": ""], quote: "kal tak",
            run: run)
        try store.saveReading(
            .init(items: [fact], dropped: 0, run: run), of: old, day: today, scope: "",
            grant: try await store.grant(for: .whatsapp, label: "team", at: noon))
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "Kabir" }, notifier: FakeNotifier())
        let model = TodayModel(store: store, crew: crew)
        #expect(!model.isEmpty, "a day with facts never says it has nothing")
        #expect(model.unsummarized.map(\.name) == ["Asha"])
    }
}
