import Foundation
import Synchronization
import WorkbenchCore

@testable import AgentCLI

struct Verdict: Decodable, Sendable, Equatable {
    var label: String
    static var schema: JSONSchema { .object([.init("label", .string)]) }
}

/// Returns one fixed output and remembers each plan it was asked to run.
final class FakeLauncher: ProcessLauncher, Sendable {
    let output: ProcessOutput
    private let launched = Mutex<[ProcessPlan]>([])

    init(output: ProcessOutput) { self.output = output }

    var plans: [ProcessPlan] { launched.withLock { $0 } }

    func launch(_ plan: ProcessPlan, timeout: Duration) async throws -> ProcessOutput {
        launched.withLock { $0.append(plan) }
        return output
    }
}

let sampleCall = AgentCall(
    prompt: "the input", instructions: "the rules", schemaText: try! Verdict.schema.jsonText, model: "m",
    effort: "low", timeout: .seconds(5))

let noisyEnvironment = [
    "HOME": "/Users/me", "USER": "me", "LANG": "en_US.UTF-8", "TMPDIR": "/tmp/x/", "SHELL": "/bin/zsh",
    "ANTHROPIC_API_KEY": "k", "ANTHROPIC_AUTH_TOKEN": "t", "OPENAI_API_KEY": "k", "CODEX_API_KEY": "k",
    "CLAUDECODE": "1",
    "CLAUDE_CODE_SESSION_ID": "s", "OPENAI_BASE_URL": "u",
]

func makePlan(_ call: AgentCall = sampleCall, kind: AgentCLIKind = .claude) -> ProcessPlan {
    ProcessPlan.make(
        call: call, kind: kind, executable: tool(kind), environment: noisyEnvironment,
        workDirectory: URL(fileURLWithPath: "/tmp/work"))
}

/// Where the tests pretend the CLI is installed.
func tool(_ kind: AgentCLIKind) -> URL { URL(fileURLWithPath: "/opt/tools/\(kind.rawValue)") }
