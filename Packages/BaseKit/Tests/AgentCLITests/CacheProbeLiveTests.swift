import Foundation
import Testing
import WorkbenchCore

@testable import AgentCLI

/// Runs five alternating calls of two tasks through the real CLI and prints the cache read share and the cost.
@Suite struct CacheProbeLiveTests {
    private static let live = ProcessInfo.processInfo.environment["WORKBENCH_LIVE_CACHE_PROBE"] == "1"

    private struct Items: Decodable, Sendable {
        struct Item: Decodable, Sendable { var text: String }
        var items: [Item]
        static var schema: JSONSchema { .object([.init("items", .array(.object([.init("text", .string)])))]) }
    }

    private static let tasks: [(instructions: String, input: String)] = [
        (
            "You keep the facts of a founder's company from its work chats. Give one item for each fact a message states, with the person it is about. Use only what a message says.",
            "[1] 10:02 Rahul — I will finish the API by Friday."
        ),
        (
            "You read inbound deals for a venture investor from mail threads. For each startup that pitches, give one item with what the mail says about it.",
            "[1] Asha — Acme raises a seed round of $1M for its billing tool."
        ),
    ]

    @Test(.enabled(if: live)) func fiveAlternatingCallsReadMostOfTheirPromptFromTheCache() async throws {
        let work = FileManager.default.temporaryDirectory.appending(path: "d5-probe-work")
        let runner = AgentRunner(
            kind: .claude, model: "claude-sonnet-5-5", effort: "low", timeout: .seconds(180),
            workDirectory: work)
        var usage = Usage()
        for index in 0..<5 {
            let task = Self.tasks[index % 2]
            let answer = try await runner.generate(
                Items.self, schema: Items.schema, instructions: task.instructions, input: task.input)
            usage = usage + answer.usage
            print("PROBE call \(index) read \(answer.usage.cacheReadTokens) write \(answer.usage.cacheWriteTokens)")
        }
        let share = Double(usage.cacheReadTokens) / Double(max(1, usage.cacheReadTokens + usage.cacheWriteTokens))
        print(
            "PROBE read \(usage.cacheReadTokens) write \(usage.cacheWriteTokens) share \(share) usd/call \(usage.costUSD / 5)"
        )
        #expect(share >= 0.8)
    }
}
