import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

private struct Priced: StructuredModel {
    let model: String
    let usage: Usage
    var name: String { "claude \(model)" }

    func generate<T: Decodable & Sendable>(_ type: T.Type, schema: JSONSchema, instructions: String, input: String)
        async throws -> ModelAnswer<T>
    {
        ModelAnswer(
            value: try JSONDecoder().decode(T.self, from: Data("{}".utf8)), model: model, usage: usage, reply: "{}")
    }
}

nonisolated private struct Empty: Decodable, Sendable {}

@Suite struct UsageReportTests {
    private let noon: Date = {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_790_000_000))!
    }()

    private func call(_ task: String, _ model: String, _ usage: Usage, daysAgo: Int, clock: TestClock, store: Store)
        async throws
    {
        clock.set(Calendar.current.date(byAdding: .day, value: -daysAgo, to: noon)!)
        _ = try await RecordedModel(Priced(model: model, usage: usage), store: store).generate(
            Empty.self, schema: .object([]), task: task, instructions: "", input: "x", holding: [])
    }

    private func runs() async throws -> [Run] {
        let clock = TestClock(noon)
        let store = try scratchStore(clock: { clock.now })
        try await call(
            "team.ledger", "claude-opus-5-5",
            Usage(inputTokens: 6, cacheReadTokens: 32_090, cacheWriteTokens: 14_470, outputTokens: 529, costUSD: 0.003),
            daysAgo: 0, clock: clock, store: store)
        try await call(
            "mochi.brief", "claude-sonnet-5-5", Usage(inputTokens: 100, outputTokens: 50, costUSD: 0.001), daysAgo: 2,
            clock: clock, store: store)
        try await call(
            "team.ledger", "gpt-6.2-sol", Usage(inputTokens: 1_000, outputTokens: 10), daysAgo: 2, clock: clock,
            store: store)
        try await call(
            "team.ledger", "claude-opus-5-5", Usage(inputTokens: 9, costUSD: 5), daysAgo: 40, clock: clock, store: store
        )
        return try store.queries.runs()
    }

    private let names = { (task: String) in task == "team.ledger" ? "Pip" : "Mochi" }

    @Test func aPeriodAddsUpItsCallsByModelMachineAndDay() async throws {
        let report = UsageReport(runs: try await runs(), days: 7, now: noon, name: names)
        #expect(report.calls == 3 && report.runs.map(\.task) == ["team.ledger", "mochi.brief", "team.ledger"])
        #expect(abs(report.total.costUSD - 0.004) < 1e-9)
        #expect(report.total.tokens == 6 + 32_090 + 14_470 + 529 + 150 + 1_010)
        #expect(report.byModel.map(\.name) == ["Claude Opus 5.5", "Claude Sonnet 5.5", "gpt-6.2-sol"])
        #expect(report.byMachine.map(\.name) == ["Pip", "Mochi"])
        #expect(report.byMachine.first?.calls == 2)
        #expect(report.byDay.count == 7)
        #expect(report.byDay.last?.day == Calendar.current.startOfDay(for: noon))
        #expect(report.byDay.map(\.usage.costUSD).filter { $0 > 0 }.count == 2)
    }

    @Test func modelNamesReadLikeTheirProduct() {
        #expect(UsageReport.modelName("claude-opus-5-5") == "Claude Opus 5.5")
        #expect(UsageReport.modelName("claude-haiku-4-5-20251001") == "Claude Haiku 4.5")
        #expect(UsageReport.modelName("claude opus") == "Claude Opus")
        #expect(UsageReport.modelName("gpt-6.2-sol") == "gpt-6.2-sol")
    }
}
