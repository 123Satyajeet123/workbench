import Foundation

@testable import AgentCLI

// Shows what a model call's process may load and offer, in both directions, on made-up data. The plan checks need no
// network and no CLI. `--live` also runs the installed Claude CLI once and reads what it loaded.
// Usage: model-call-check [--live]
setvbuf(stdout, nil, _IOLBF, 0)
let arguments = Array(CommandLine.arguments.dropFirst())

var failures = 0

func check(_ condition: Bool, _ words: String) {
    if !condition { failures += 1 }
    print("  \(condition ? "yes" : "NO ") \(words)")
}

func refused(_ plan: ProcessPlan) -> Bool {
    do {
        try plan.validate()
        return false
    } catch { return true }
}

func value(after flag: String, in plan: ProcessPlan) -> String? {
    plan.arguments.firstIndex(of: flag).map { plan.arguments[$0 + 1] }
}

func changed(_ plan: ProcessPlan, _ flag: String, to value: String) -> ProcessPlan {
    var plan = plan
    if let index = plan.arguments.firstIndex(of: flag) { plan.arguments[index + 1] = value }
    return plan
}

let shell = ["HOME": "/Users/me", "USER": "me", "PATH": "/usr/bin", "ANTHROPIC_API_KEY": "sk-ant-from-the-shell"]
    .merging(["CLAUDE_CODE_USE_BEDROCK": "1", "OPENAI_API_KEY": "sk-other", "ANTHROPIC_AUTH_TOKEN": "t"]) { $1 }
let schema =
    #"{"additionalProperties":false,"properties":{"word":{"type":"string"}},"required":["word"],"type":"object"}"#

func call(_ tools: AgentTools) -> AgentCall {
    AgentCall(
        prompt: "Day 2026-01-05.",
        instructions: "Call the tool get_lines for the day in the data and give the secret word it states.",
        schemaText: schema, model: "claude-haiku-5-5", effort: "low", timeout: .seconds(120), tools: tools)
}

func plan(_ tools: AgentTools, kind: AgentCLIKind = .claude, in folder: URL = URL(filePath: "/tmp/w")) -> ProcessPlan {
    ProcessPlan.make(
        call: call(tools), kind: kind, executable: URL(filePath: "/opt/tools/\(kind.rawValue)"), environment: shell,
        workDirectory: folder)
}

let plain = plan(.none)

print("\nG2 a call with no tools names no server, and has auto memory and hooks off")
check(!refused(plain), "the plan of a call with no tools passes")
check(value(after: "--mcp-config", in: plain) == #"{"mcpServers":{}}"#, "it names no server")
check(!plain.arguments.contains("--allowedTools") && !plain.arguments.contains("--max-turns"), "it allows no tool")
check(
    value(after: "--settings", in: plain) == #"{"autoMemoryEnabled":false,"disableAllHooks":true}"#,
    "auto memory and hooks are off")
check(refused(changed(plain, "--settings", to: "{}")), "a plan that leaves auto memory on is refused")
check(refused(changed(plain, "--setting-sources", to: "user")), "a plan that reads the person's settings is refused")
check(
    refused(changed(plain, "--mcp-config", to: #"{"mcpServers":{"x":{"command":"/bin/sh"}}}"#)),
    "a plan that names a server is refused")

print("\nG5 no credential of the shell reaches the child")
for name in ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "OPENAI_API_KEY", "CLAUDE_CODE_USE_BEDROCK"] {
    check(plain.environment[name] == nil, "\(name) is not in the child's environment")
}
var leaking = plain
leaking.environment["ANTHROPIC_API_KEY"] = "sk-ant-from-the-shell"
check(refused(leaking), "a plan that carries the shell's key is refused")

if arguments.contains("--live") { await Live.run() }

print(failures == 0 ? "\nALL OK" : "\n\(failures) CHECKS FAILED")
exit(failures == 0 ? 0 : 1)
