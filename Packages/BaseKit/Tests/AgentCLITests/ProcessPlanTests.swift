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
