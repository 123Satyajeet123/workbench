import Foundation
import Testing
import WorkbenchCore

@testable import AgentCLI

@Suite struct AgentRunnerTests {
    private func runner(_ launcher: FakeLauncher, kind: AgentCLIKind = .claude) -> AgentRunner {
        AgentRunner(
            kind: kind, model: kind == .claude ? "opus" : "gpt-6", effort: "low", timeout: .seconds(5),
            launcher: launcher, executable: tool(kind), environment: noisyEnvironment)
    }

    @Test func theInstalledCLIIsFoundOnThePathFirstThenInTheInstallerFolders() {
        let home = URL(fileURLWithPath: "/Users/me")
        let present: Set = ["/usr/bin/claude", "/Users/me/.local/bin/claude", "/opt/homebrew/bin/codex"]
        let found = { (kind: AgentCLIKind, path: String) in
            kind.installed(environment: ["PATH": path], home: home, isExecutable: present.contains)?.path
        }
        #expect(found(.claude, "/usr/bin:/bin") == "/usr/bin/claude")
        #expect(found(.claude, "/bin") == "/Users/me/.local/bin/claude")
        #expect(found(.codex, "") == "/opt/homebrew/bin/codex")
        #expect(AgentCLIKind.codex.installed(environment: [:], home: home, isExecutable: { _ in false }) == nil)
    }

    @Test func aCallWithNoInstalledCLIFailsBeforeAnyProcessStarts() async throws {
        let launcher = reply(#""is_error":false,"result":"{}""#)
        var runner = runner(launcher)
        runner.executable = nil
        await #expect(throws: AgentCLIError.notInstalled(.claude)) {
            _ = try await runner.generate(Verdict.self, schema: Verdict.schema, instructions: "", input: "x")
        }
        #expect(launcher.plans.isEmpty)
    }

    private func reply(_ fields: String) -> FakeLauncher {
        FakeLauncher(output: ProcessOutput(stdout: #"{"type":"system"}"# + "\n" + #"{"type":"result",\#(fields)}"#))
    }

    @Test func theAnswerCarriesTheValueTheReportedModelAndTheUsage() async throws {
        let launcher = reply(
            #""is_error":false,"structured_output":{"label":"yes"},"total_cost_usd":0.5,"modelUsage":{"claude-opus-5-5":{"inputTokens":10,"outputTokens":4,"cacheReadInputTokens":100,"cacheCreationInputTokens":20,"costUSD":0.45},"claude-haiku-5-5":{"inputTokens":1,"outputTokens":1,"costUSD":0.05}}"#
        )
        let answer = try await runner(launcher).generate(
            Verdict.self, schema: Verdict.schema, instructions: "rules", input: "input")
        #expect(answer.value == Verdict(label: "yes"))
        #expect(answer.model == "claude-opus-5-5")
        #expect(
            answer.usage
                == Usage(inputTokens: 11, cacheReadTokens: 100, cacheWriteTokens: 20, outputTokens: 5, costUSD: 0.5))
        let plan = try #require(launcher.plans.first)
        #expect(plan.stdin == "rules\n\ninput")
        #expect(plan.arguments.contains("opus"))
    }

    @Test func withoutModelUsageTheAnswerNamesTheModelAskedForAndCostsNothing() async throws {
        let answer = try await runner(reply(#""is_error":false,"result":"{\"label\":\"txt\"}""#)).generate(
            Verdict.self, schema: Verdict.schema, instructions: "", input: "p")
        #expect(answer.value == Verdict(label: "txt"))
        #expect(answer.model == "opus")
        #expect(answer.usage == Usage())
    }

    @Test func anErrorResultIsUnavailable() async {
        await #expect(throws: StructuredModelError.unavailable("claude failed: rate limited")) {
            try await runner(reply(#""is_error":true,"result":"rate limited""#)).generate(
                Verdict.self, schema: Verdict.schema, instructions: "", input: "p")
        }
    }

    @Test func noResultIsUnavailable() async {
        await #expect(throws: StructuredModelError.unavailable("claude exit 1: boom")) {
            try await runner(FakeLauncher(output: ProcessOutput(stdout: "", stderr: "boom", status: 1))).generate(
                Verdict.self, schema: Verdict.schema, instructions: "", input: "p")
        }
    }

    @Test func aReplyThatDoesNotDecodeIsInvalid() async {
        do {
            _ = try await runner(reply(#""is_error":false,"structured_output":{"other":1}"#)).generate(
                Verdict.self, schema: Verdict.schema, instructions: "", input: "p")
            Issue.record("the reply should not decode")
        } catch StructuredModelError.invalidReply {
            return
        } catch {
            Issue.record("wrong error \(error)")
        }
    }

    @Test func codexAnswersFromItsFileWithTheTokensOfEveryTurn() async throws {
        let events = [
            #"{"type":"thread.started"}"#,
            #"{"type":"turn.completed","usage":{"input_tokens":1000,"cached_input_tokens":800,"output_tokens":50}}"#,
        ]
        let launcher = FakeLauncher(
            output: ProcessOutput(stdout: events.joined(separator: "\n"), answerFile: #"{"label":"codex"}"#))
        let answer = try await runner(launcher, kind: .codex).generate(
            Verdict.self, schema: Verdict.schema, instructions: "", input: "p")
        #expect(answer.value == Verdict(label: "codex"))
        #expect(answer.model == "gpt-6")
        #expect(answer.usage == Usage(inputTokens: 200, cacheReadTokens: 800, outputTokens: 50))
        #expect(launcher.plans.first?.inputFiles[ProcessPlan.schemaFileName] == sampleCall.schemaText)
    }

    @Test func codexWithoutAnAnswerOrWithAFailedTurnIsRefused() async {
        await #expect(throws: StructuredModelError.invalidReply("codex wrote no answer")) {
            try await runner(FakeLauncher(output: ProcessOutput(stdout: #"{"type":"turn.completed"}"#)), kind: .codex)
                .generate(Verdict.self, schema: Verdict.schema, instructions: "", input: "p")
        }
        let failed = ProcessOutput(
            stdout: #"{"type":"turn.failed","error":{"message":"usage limit"}}"#, answerFile: #"{"label":"x"}"#)
        await #expect(throws: StructuredModelError.unavailable("codex failed: usage limit")) {
            try await runner(FakeLauncher(output: failed), kind: .codex).generate(
                Verdict.self, schema: Verdict.schema, instructions: "", input: "p")
        }
    }

    @Test func theRunnerIsNamedByItsCLIAndModel() {
        #expect(runner(reply("")).name == "claude opus")
        #expect(runner(reply(""), kind: .codex).name == "codex gpt-6")
    }
}

@Suite struct LiveCLITests {
    private static let live = ProcessInfo.processInfo.environment["WORKBENCH_LIVE_CLI"] == "1"

    @Test(.enabled(if: live), arguments: [(AgentCLIKind.claude, "haiku"), (.claude, "opus"), (.codex, "gpt-6.2-sol")])
    func aHarmlessPromptRoundTripsThroughTheInstalledCLI(kind: AgentCLIKind, model: String) async throws {
        let runner = AgentRunner(kind: kind, model: model, effort: "low", timeout: .seconds(180))
        let started = ContinuousClock.now
        let answer = try await runner.generate(
            Verdict.self, schema: Verdict.schema, instructions: "Return the label \"pong\".", input: "ping")
        print("live \(kind) model=\(answer.model) seconds=\(ContinuousClock.now - started) usage=\(answer.usage)")
        #expect(!answer.value.label.isEmpty)
        #expect(answer.usage.tokens > 0)
    }
}
