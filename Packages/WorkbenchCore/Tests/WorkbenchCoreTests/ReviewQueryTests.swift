import Foundation
import Testing

@testable import WorkbenchCore

@Suite struct ReviewQueryTests {
    private func save(_ spec: HelperSpec, day: WorkDay, quotes: [String], pick: Int, into store: Store) async throws {
        let model = RecordedModel(ScriptedModel(#"{"items":[]}"#), store: store)
        let (_, run) = try await model.generate(
            HelperReader.Reply.self, schema: .object([]), task: spec.task, instructions: spec.brief, input: "x")
        let items = quotes.enumerated().map { index, quote in
            Item(
                task: spec.task, day: day, scope: "", source: .screen, citeFirst: Int64(index), citeLast: Int64(index),
                start: day.start.addingTimeInterval(Double(index) * 600),
                end: day.start.addingTimeInterval(Double(index) * 600 + 300), fields: ["task": quote], quote: quote,
                run: run)
        }
        try store.saveReading(
            .init(items: items, dropped: 0, run: run), of: spec, day: day, scope: "", grant: grant(.screen),
            pick: { _ in pick })
    }

    @Test func theQueueHoldsEveryMachinesUnmarkedItemsWithTheAppsPicksFirst() async throws {
        let store = try makeStore()
        let today = WorkDay(containing: t0)
        var other = HelperSpec.timeline
        other.task = "day.timeline-2"
        try await save(.timeline, day: today, quotes: ["a", "b"], pick: 1, into: store)
        try await save(other, day: today.adding(days: -1), quotes: ["c", "d"], pick: 0, into: store)
        try await save(.timeline, day: today.adding(days: -9), quotes: ["old"], pick: 0, into: store)
        var waiting = try store.queries.waitingItems(since: today.adding(days: -7))
        #expect(waiting.map(\.quote) == ["b", "c", "a", "d"])
        #expect(Set(waiting.map(\.task)) == [HelperSpec.timeline.task, "day.timeline-2"])
        try store.mark(item: try #require(waiting.first?.id), as: .confirmed)
        waiting = try store.queries.waitingItems(since: today.adding(days: -7))
        #expect(waiting.map(\.quote) == ["c", "a", "d"])
    }
}
