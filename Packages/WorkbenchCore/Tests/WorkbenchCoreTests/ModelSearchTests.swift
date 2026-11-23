import Foundation
import Synchronization
import Testing

@testable import WorkbenchCore

/// Answers with a fixed reply, and records the outcome of every run the store held while the call was open.
private final class ProbingModel: StructuredModel, Sendable {
    let name = "probing"
    let store: Store
    let reply: String
    let outcomesDuringCall = Mutex<[[Run.Outcome]]>([])

    init(store: Store, reply: String) {
        self.store = store
        self.reply = reply
    }

    func generate<T: Decodable & Sendable>(_ type: T.Type, schema: JSONSchema, instructions: String, input: String)
        async throws -> ModelAnswer<T>
    {
        outcomesDuringCall.withLock { $0.append((try? store.queries.runs())?.map(\.outcome) ?? []) }
        return ModelAnswer(
            value: try JSONDecoder().decode(T.self, from: Data(reply.utf8)), model: "probing-1",
            usage: Usage(costUSD: 0.034), reply: reply)
    }
}

@Suite struct ModelSearchTests {
    private let reply = """
        {"results":[{"title":"Acme raises","url":"https://news.example/a"},\
        {"title":"Acme site","url":"https://acme.example/"},{"title":"Third","url":"https://c.example/"}]}
        """

    @Test func aScriptedReplyBecomesHitsWithTheirTitlesAndAtMostTheCount() async throws {
        let store = try makeStore()
        let search = ModelSearch(model: RecordedModel(ScriptedModel(reply), store: store))
        let hits = try await search.search("Acme seed round", count: 2)
        #expect(hits.map(\.url.absoluteString) == ["https://news.example/a", "https://acme.example/"])
        #expect(hits.map(\.title) == ["Acme raises", "Acme site"])
    }

    @Test func aReplyThatDoesNotFitTheSchemaGivesNoHitsAndAFailedRun() async throws {
        let store = try makeStore()
        let model = ScriptedModel(failing: .invalidReply("the reply does not fit the schema"))
        let hits = try await ModelSearch(model: RecordedModel(model, store: store)).search("q", count: 5)
        let run = try #require(try store.queries.runs().first)
        #expect(hits.isEmpty && run.outcome == .failed && run.task == ModelSearch.task)
    }

    @Test func aModelThatIsNotAvailableStillThrowsInsteadOfGivingNoHits() async throws {
        let store = try makeStore()
        let model = ScriptedModel(failing: .unavailable("claude is not installed"))
        await #expect(throws: StructuredModelError.self) {
            try await ModelSearch(model: RecordedModel(model, store: store)).search("q", count: 5)
        }
    }

    @Test func theRunRowIsOpenBeforeTheCallLeavesAndFinishedWithItsCost() async throws {
        let store = try makeStore()
        let model = ProbingModel(store: store, reply: reply)
        _ = try await ModelSearch(model: RecordedModel(model, store: store)).search("Acme", count: 5)
        #expect(model.outcomesDuringCall.withLock { $0 } == [[.running]])
        let run = try #require(try store.queries.runs().first)
        #expect(run.outcome == .done && run.task == ModelSearch.task && run.usage.costUSD == 0.034)
        #expect(try store.queries.runText(of: run.id)?.kinds == [.web])
    }

    @Test func aFailedCallFinishesItsRunWithNoCost() async throws {
        let store = try makeStore()
        let model = ScriptedModel(failing: .unavailable("offline"))
        _ = try? await ModelSearch(model: RecordedModel(model, store: store)).search("Acme", count: 5)
        let run = try #require(try store.queries.runs().first)
        #expect(run.outcome == .failed && run.usage.costUSD == 0 && run.error != nil)
    }

    @Test func withWebResearchOffNoSearchCallLeavesAndNoRunIsWritten() async throws {
        let store = try makeStore()
        let model = ScriptedModel(reply)
        func open() throws -> WebSession {
            try WebSession.open(
                store: store, key: { _ in nil },
                make: { _, _, _ in (ModelSearch(model: RecordedModel(model, store: store)), FakePages()) })
        }
        #expect(throws: WebBlock.consentOff) { try open() }
        let runsAfterRefusal = try store.queries.runs()
        #expect(model.inputs.withLock { $0 }.isEmpty && runsAfterRefusal.isEmpty)

        try store.switchWeb(true)
        let hits = try await open().search("Acme", count: 5)
        #expect(hits.count == 3 && model.inputs.withLock { $0 }.count == 1)
    }
}
