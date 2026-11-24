import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

nonisolated private let limits = PlanLimits(
    fiveHour: .init(used: 0.1, resetsAt: Date(timeIntervalSince1970: 1_795_455_600), isAtLimit: false),
    week: .init(used: 0.39, resetsAt: Date(timeIntervalSince1970: 1_795_867_200), isAtLimit: false),
    at: Date(timeIntervalSince1970: 1_795_440_000))

private struct ReportsLimits: StructuredModel {
    let store: Store
    let fails: Bool
    var name: String { "claude haiku" }

    func generate<T: Decodable & Sendable>(_ type: T.Type, schema: JSONSchema, instructions: String, input: String)
        async throws -> ModelAnswer<T>
    {
        await PlanUsage.record(limits, in: store)
        if fails { throw StructuredModelError.unavailable("claude failed: limit") }
        let reply = #"{"ok":true}"#
        return ModelAnswer(
            value: try JSONDecoder().decode(T.self, from: Data(reply.utf8)), model: "claude-haiku-5-5",
            usage: Usage(inputTokens: 3, outputTokens: 2, costUSD: 0.0001), reply: reply)
    }
}

@Suite struct PlanUsageTests {
    private func settled(_ usage: PlanUsage) async throws {
        for _ in 0..<50 where usage.limits == nil { try await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func limitsAClaudeCallReportsReachTheRingAndSurviveARestart() async throws {
        let store = try scratchStore()
        let usage = PlanUsage(store: store)
        #expect(usage.limits == nil)
        PlanUsage.record(limits, in: store)
        try await settled(usage)
        #expect(usage.limits == limits)
        #expect(PlanUsage(store: store).limits == limits)
    }

    @Test func refreshingAsksClaudeOnceAndCountsThatCallAsUsage() async throws {
        let store = try scratchStore()
        let usage = PlanUsage(store: store) { RecordedModel(ReportsLimits(store: store, fails: false), store: store) }
        await usage.refresh()
        #expect(usage.limits == limits && usage.problem == nil && !usage.isRefreshing)
        let runs = try store.queries.runs()
        #expect(runs.map(\.task) == ["usage.refresh"] && runs.first?.usage?.costUSD == 0.0001)
    }

    @Test func aRefreshThatFailsAtTheLimitStillShowsTheLimitAndSaysWhy() async throws {
        let store = try scratchStore()
        let usage = PlanUsage(store: store) { RecordedModel(ReportsLimits(store: store, fails: true), store: store) }
        await usage.refresh()
        #expect(usage.limits == limits && usage.problem != nil)
    }
}
