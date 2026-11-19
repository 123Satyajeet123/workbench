import Foundation
import Testing
import WorkbenchCore

@testable import AgentCLI

@Suite struct ProcessPlanTests {
    private func value(after flag: String, in plan: ProcessPlan) -> String? {
        plan.arguments.firstIndex(of: flag).map { plan.arguments[$0 + 1] }
    }

    @Test func aCallBecomesAPlanWithNoToolsNoServersNoSettingsAndNoSession() throws {
        let plan = makePlan()
        try plan.validate()
        #expect(value(after: "--tools", in: plan) == "")
        #expect(value(after: "--setting-sources", in: plan) == "")
        #expect(value(after: "--mcp-config", in: plan) == #"{"mcpServers":{}}"#)
        #expect(value(after: "--permission-mode", in: plan) == "dontAsk")
        #expect(plan.arguments.contains("--no-session-persistence"))
        #expect(value(after: "--json-schema", in: plan) == sampleCall.schemaText)
        #expect(plan.stdin == sampleCall.promptText)
    }

    @Test func secretsAndHostVariablesNeverReachTheChildAndTheKillSwitchesDo() {
        let plan = makePlan()
        #expect(plan.environment.keys.filter(ProcessPlan.isForbidden).isEmpty)
        #expect(plan.environment["SHELL"] == nil)
        #expect(plan.environment["HOME"] == "/Users/me")
        for name in ["DISABLE_AUTOUPDATER", "DISABLE_TELEMETRY", "DISABLE_ERROR_REPORTING"] {
            #expect(plan.environment[name] == "1")
        }
    }

    @Test(arguments: ["ANTHROPIC_API_KEY", "OPENAI_API_KEY", "CODEX_API_KEY", "CLAUDE_CODE_OAUTH_TOKEN", "CLAUDECODE"])
    func aPlanCarryingASecretFailsValidation(name: String) {
        for kind in AgentCLIKind.allCases {
            var plan = makePlan(kind: kind)
            plan.environment[name] = "x"
            #expect(throws: AgentCLIError.self) { try plan.validate() }
        }
    }

    @Test(arguments: [
        ("--tools", "Bash"), ("--setting-sources", "user"), ("--permission-mode", "bypassPermissions"),
        ("--mcp-config", #"{"mcpServers":{"x":{"command":"/bin/sh"}}}"#),
    ])
    func aPlanThatCouldActOrReadSettingsFailsValidation(flag: String, value: String) throws {
        var plan = makePlan()
        plan.arguments[try #require(plan.arguments.firstIndex(of: flag)) + 1] = value
        #expect(throws: AgentCLIError.self) { try plan.validate() }
    }

    @Test(arguments: ["--no-session-persistence", "--strict-mcp-config", "--disable-slash-commands"])
    func aPlanMissingAGuardFlagFailsValidation(flag: String) {
        var plan = makePlan()
        plan.arguments.removeAll { $0 == flag }
        #expect(throws: AgentCLIError.self) { try plan.validate() }
    }

    @Test(arguments: [["--resume", "s"], ["--allowedTools", "Bash"]])
    func aPlanThatResumesOrAllowsToolsFailsValidation(extra: [String]) {
        var plan = makePlan()
        plan.arguments += extra
        #expect(throws: AgentCLIError.self) { try plan.validate() }
    }
}

@Suite struct CodexPlanTests {
    @Test func aCodexCallIsEphemeralReadOnlyWithoutToolsOrSearch() throws {
        let plan = makePlan(kind: .codex)
        try plan.validate()
        #expect(plan.inputFiles == [ProcessPlan.schemaFileName: sampleCall.schemaText])
        #expect(plan.answerFile == ProcessPlan.answerFileName)
        #expect(plan.environment["DISABLE_TELEMETRY"] == nil)
    }

    @Test(arguments: ["shell_tool", "unified_exec", "view_image"])
    func aCodexPlanThatLeavesAToolOnFailsValidation(feature: String) throws {
        var plan = makePlan(kind: .codex)
        let index = try #require(plan.arguments.firstIndex(of: feature))
        plan.arguments.removeSubrange((index - 1)...index)
        #expect(throws: AgentCLIError.self) { try plan.validate() }
    }

    @Test func aCodexPlanThatWritesSearchesOrNamesAServerFailsValidation() throws {
        var writable = makePlan(kind: .codex)
        writable.arguments[try #require(writable.arguments.firstIndex(of: "read-only"))] = "workspace-write"
        #expect(throws: AgentCLIError.self) { try writable.validate() }
        var searching = makePlan(kind: .codex)
        searching.arguments[try #require(searching.arguments.firstIndex(of: #"web_search="disabled""#))] =
            #"web_search="live""#
        #expect(throws: AgentCLIError.self) { try searching.validate() }
        var server = makePlan(kind: .codex)
        server.arguments += ["--config", #"mcp_servers.x.command="/bin/sh""#]
        #expect(throws: AgentCLIError.self) { try server.validate() }
    }
}

@Suite struct ClaudeResultTests {
    @Test func aSuccessCarriesTheStructuredAnswerTheUsageAndTheCostliestModel() throws {
        let line =
            #"{"type":"result","subtype":"success","is_error":false,"result":"","structured_output":{"a":1},"total_cost_usd":0.25,"modelUsage":{"a":{"inputTokens":3,"cacheCreationInputTokens":4,"cacheReadInputTokens":5,"outputTokens":6,"costUSD":0.2},"b":{"inputTokens":1,"costUSD":0.05}}}"#
        let result = try #require(ClaudeResult(line: line))
        #expect(!result.isError)
        #expect(result.structuredAnswer == #"{"a":1}"#)
        #expect(result.model == "a")
        #expect(
            result.usage
                == Usage(inputTokens: 4, cacheReadTokens: 5, cacheWriteTokens: 4, outputTokens: 6, costUSD: 0.25))
    }

    @Test func anErrorOrAnErrorSubtypeIsAnError() throws {
        #expect(try #require(ClaudeResult(line: #"{"type":"result","is_error":true,"result":"limit"}"#)).isError)
        #expect(
            try #require(ClaudeResult(line: #"{"type":"result","subtype":"error_max_turns","is_error":false}"#)).isError
        )
        #expect(try !#require(ClaudeResult(line: #"{"type":"result","subtype":"success","is_error":false}"#)).isError)
    }

    @Test func otherEventsAreNotResults() {
        #expect(ClaudeResult(line: #"{"type":"assistant"}"#) == nil)
        #expect(ClaudeResult(line: "not json") == nil)
        #expect(ClaudeResult.last(in: #"{"type":"system"}"#) == nil)
    }
}

@Suite struct SchemaTextTests {
    @Test func anObjectSchemaIsStrictWithAllPropertiesRequired() throws {
        let schema = JSONSchema.object([
            .init("name", .string), .init("ok", .boolean), .init("n", .number),
            .init("kind", .enumeration(["a", "b"])), .init("tags", .array(.string)),
        ])
        let text = try schema.jsonText
        #expect(text.contains(#""additionalProperties":false"#))
        #expect(text.contains(#""required":["name","ok","n","kind","tags"]"#))
        #expect(text.contains(#""kind":{"enum":["a","b"],"type":"string"}"#))
        #expect(text.contains(#""tags":{"items":{"type":"string"},"type":"array"}"#))
    }
}
