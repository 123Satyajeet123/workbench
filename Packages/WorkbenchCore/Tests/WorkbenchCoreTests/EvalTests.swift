import Foundation
import Testing

@testable import WorkbenchCore

@Suite struct EvalSplitTests {
    private let days = (0..<1000).map { WorkDay(containing: t0.addingTimeInterval(Double($0) * 86_400)) }

    @Test func aboutThreeDaysInTenAreHeldOutAndEachDayAlwaysFallsTheSameWay() {
        let heldOut = days.filter { EvalSplit($0) == .heldOut }.count
        #expect((250...350).contains(heldOut))
        #expect(days.allSatisfy { EvalSplit($0) == EvalSplit(WorkDay($0.description)!) })
    }

    @Test func marksOnHeldOutDaysCountApartFromDevDays() async throws {
        let dev = try #require(days.first { EvalSplit($0) == .dev })
        let heldOut = try #require(days.first { EvalSplit($0) == .heldOut })
        let store = try makeStore()
        let model = RecordedModel(ScriptedModel(#"{"items":[]}"#), store: store)
        let (_, run) = try await model.generate(
            HelperReader.Reply.self, schema: .object([]), task: "day.timeline", instructions: "v1", input: "x")
        for (day, marks) in [(dev, [Mark.confirmed, .rejected]), (heldOut, [.confirmed])] {
            let items = marks.indices.map { index in
                Item(
                    task: "day.timeline", day: day, scope: "", source: .screen, citeFirst: Int64(index),
                    citeLast: Int64(index), start: day.start.addingTimeInterval(Double(index) * 600),
                    end: day.start.addingTimeInterval(Double(index) * 600 + 300), fields: ["task": "t\(index)"],
                    quote: "q", run: run)
            }
            try store.saveReading(
                .init(items: items, dropped: 0, run: run), of: .timeline, day: day, scope: "", grant: grant(.screen))
            for (item, mark) in zip(try store.queries.items(of: "day.timeline", day: day, scope: ""), marks) {
                try store.mark(item: try #require(item.id), as: mark)
            }
        }
        let quality = try #require(store.queries.quality().first)
        #expect(quality.dev == Tally(confirmed: 1, rejected: 1))
        #expect(quality.heldOut == Tally(confirmed: 1, rejected: 0))
        #expect(quality.all.precision == 2.0 / 3.0)
    }
}

@Suite struct PromptVersionTests {
    @Test func eachNewInstructionTextIsKeptOnceAndNumberedInOrder() async throws {
        let store = try makeStore()
        let model = RecordedModel(ScriptedModel(#"{"items":[]}"#), store: store)
        for instructions in ["first", "first", "second"] {
            _ = try await model.generate(
                HelperReader.Reply.self, schema: .object([]), task: "day.timeline", instructions: instructions,
                input: "x")
        }
        let versions = try store.queries.prompts(task: "day.timeline")
        #expect(versions.map(\.instructions) == ["first", "second"])
        #expect(versions.map(\.number) == [1, 2])
        let quality = try store.queries.quality()
        #expect(Set(quality.compactMap(\.version)) == [1, 2])
        #expect(quality.first { $0.version == 1 }?.runs == 2)
        #expect(try store.queries.prompts(task: "team.ledger").isEmpty)
    }
}
