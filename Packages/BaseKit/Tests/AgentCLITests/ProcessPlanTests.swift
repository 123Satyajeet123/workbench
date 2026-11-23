import Foundation
import Testing
import WorkbenchCore

@testable import AgentCLI

@Suite struct ProcessPlanTests {
    private func value(after flag: String, in plan: ProcessPlan) -> String? {
        plan.arguments.firstIndex(of: flag).map { plan.arguments[$0 + 1] }
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

    @Test(arguments: [
        ("--tools", "Bash"), ("--setting-sources", "user"), ("--permission-mode", "bypassPermissions"),
        ("--mcp-config", #"{"mcpServers":{"x":{"command":"/bin/sh"}}}"#),
    ])
    func aPlanThatCouldActOrReadSettingsFailsValidation(flag: String, value: String) throws {
        var plan = makePlan()
        plan.arguments[try #require(plan.arguments.firstIndex(of: flag)) + 1] = value
        #expect(throws: AgentCLIError.self) { try plan.validate() }
    }

    private var searchCall: AgentCall {
        var call = sampleCall
        call.tools = .webSearch
        return call
    }

    @Test func theSearchOnlyVariantOffersAndAllowsWebSearchAndNothingElse() throws {
        let plan = makePlan(searchCall)
        try plan.validate()
        #expect(value(after: "--tools", in: plan) == "WebSearch")
        #expect(value(after: "--allowedTools", in: plan) == "WebSearch")
        #expect(value(after: "--permission-mode", in: plan) == "dontAsk")
        #expect(value(after: "--mcp-config", in: plan) == #"{"mcpServers":{}}"#)
        #expect(makePlan().arguments.contains("--allowedTools") == false, "a plain call allows no tool")
    }

    @Test(arguments: [
        ["--tools", "WebSearch,WebFetch"], ["--tools", "WebSearch,Bash"], ["--tools", "WebFetch"],
        ["--allowedTools", "WebSearch,Bash"], ["--allowedTools", "WebFetch"],
    ])
    func aWiderToolSetThanSearchAloneFailsValidation(change: [String]) throws {
        var plan = makePlan(searchCall)
        plan.arguments[try #require(plan.arguments.firstIndex(of: change[0])) + 1] = change[1]
        #expect(throws: AgentCLIError.self) { try plan.validate() }
    }

    @Test(arguments: [["--tools", "Bash"], ["--allowedTools", "WebSearch"], ["--allowedTools", "Bash"]])
    func aSecondToolFlagOrASearchAllowanceWithoutTheToolFailsValidation(extra: [String]) throws {
        var searching = makePlan(searchCall)
        searching.arguments += extra
        #expect(throws: AgentCLIError.self) { try searching.validate() }
        var plain = makePlan()
        plain.arguments += extra
        #expect(throws: AgentCLIError.self) { try plain.validate() }
    }

    @Test func aSearchVariantWithAnMCPServerFailsValidation() throws {
        var plan = makePlan(searchCall)
        plan.arguments[try #require(plan.arguments.firstIndex(of: "--mcp-config")) + 1] =
            #"{"mcpServers":{"x":{"command":"/bin/sh"}}}"#
        #expect(throws: AgentCLIError.self) { try plan.validate() }
    }

    @Test func codexHasNoSearchVariant() throws {
        let plan = makePlan(searchCall, kind: .codex)
        #expect(throws: AgentCLIError.self) { try plan.validate() }
        try makePlan(kind: .codex).validate()
    }

    /// Anthropic's route for programs is the user's own API key; a key from the shell must still never reach the CLI.
    @Test func onlyTheKeyTheFounderChoseReachesTheClaudeCLIAndOnlyAsChosen() throws {
        let chosen = ProcessPlan.make(
            call: sampleCall, kind: .claude, executable: tool(.claude), environment: noisyEnvironment,
            workDirectory: URL(filePath: "/tmp/w"), apiKey: "sk-ant-chosen")
        #expect(chosen.environment["ANTHROPIC_API_KEY"] == "sk-ant-chosen", "not the shell's key")
        #expect(chosen.environment["OPENAI_API_KEY"] == nil && chosen.environment["ANTHROPIC_AUTH_TOKEN"] == nil)
        try chosen.validate()

        var swapped = chosen
        swapped.environment["ANTHROPIC_API_KEY"] = "sk-ant-other"
        #expect(throws: AgentCLIError.self) { try swapped.validate() }
        var stray = makePlan()
        stray.environment["ANTHROPIC_API_KEY"] = "k"
        #expect(throws: AgentCLIError.self, "a key with none chosen is refused") { try stray.validate() }
        var codex = makePlan(kind: .codex)
        codex.apiKey = "sk-ant-chosen"
        codex.environment["ANTHROPIC_API_KEY"] = "sk-ant-chosen"
        #expect(throws: AgentCLIError.self, "only the Claude CLI takes it") { try codex.validate() }
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

}
