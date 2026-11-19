import Foundation
import WorkbenchCore

/// A model behind an agent CLI, run as a child process with no tools.
public struct AgentRunner: StructuredModel {
    public let kind: AgentCLIKind
    /// Nil when the CLI is not installed; a call then fails with `notInstalled`.
    public var executable: URL?
    public var model: String
    public var effort: String
    public var timeout: Duration
    /// The founder's own Anthropic API key when billing is set to it; see `ProcessPlan.apiKey`.
    public var apiKey: String?
    /// Billing is set to an API key, so a missing key stops the call instead of falling back to the sign-in.
    public var requiresAPIKey: Bool
    private let launcher: any ProcessLauncher
    private let inheritedEnvironment: [String: String]

    public var name: String { "\(kind.rawValue) \(model)" }

    public init(
        kind: AgentCLIKind, model: String, effort: String, timeout: Duration,
        launcher: any ProcessLauncher = SystemProcessLauncher(), executable: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment, apiKey: String? = nil,
        requiresAPIKey: Bool = false
    ) {
        self.apiKey = apiKey
        self.requiresAPIKey = requiresAPIKey
        self.kind = kind
        self.executable = executable ?? kind.installed(environment: environment)
        self.model = model
        self.effort = effort
        self.timeout = timeout
        self.launcher = launcher
        inheritedEnvironment = environment
    }

    public func generate<T: Decodable & Sendable>(
        _ type: T.Type, schema: JSONSchema, instructions: String, input: String
    ) async throws -> ModelAnswer<T> {
        let call = AgentCall(
            prompt: input, instructions: instructions, schemaText: try schema.jsonText, model: model,
            effort: effort, timeout: timeout)
        let output = try await launch(call)
        let (answer, answeredBy, usage) = try kind == .claude ? claudeAnswer(output) : codexAnswer(output)
        do {
            let value = try JSONDecoder().decode(T.self, from: Data(answer.utf8))
            return ModelAnswer(value: value, model: answeredBy, usage: usage, reply: answer)
        } catch {
            throw StructuredModelError.invalidReply("\(error)")
        }
    }

    private func claudeAnswer(_ output: ProcessOutput) throws -> (String, String, Usage) {
        guard let result = ClaudeResult.last(in: output.stdout) else {
            throw StructuredModelError.unavailable("claude exit \(output.status): \(output.stderr)")
        }
        if result.isError || output.status != 0 {
            throw StructuredModelError.unavailable("claude failed: \(result.text ?? output.stderr)")
        }
        // With --json-schema the answer is `structured_output`; without it the model declined (code.claude.com/docs/en/headless).
        guard let answer = result.structuredAnswer else {
            throw StructuredModelError.invalidReply("claude declined: \(result.text ?? "no text")")
        }
        return (answer, result.model ?? model, result.usage)
    }

    private func codexAnswer(_ output: ProcessOutput) throws -> (String, String, Usage) {
        let events = CodexEvents(stdout: output.stdout)
        if output.status != 0 || events.failure != nil {
            throw StructuredModelError.unavailable("codex failed: \(events.failure ?? output.stderr)")
        }
        guard let answer = output.answerFile else { throw StructuredModelError.invalidReply("codex wrote no answer") }
        return (answer, model, events.usage)
    }

    func launch(_ call: AgentCall) async throws -> ProcessOutput {
        guard let executable else { throw AgentCLIError.notInstalled(kind) }
        if requiresAPIKey, apiKey?.isEmpty != false { throw AgentCLIError.noAPIKey }
        let files = FileManager.default
        let workDirectory = files.temporaryDirectory.appending(path: "agent-\(UUID().uuidString)")
        try files.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: workDirectory) }
        let plan = ProcessPlan.make(
            call: call, kind: kind, executable: executable, environment: inheritedEnvironment,
            workDirectory: workDirectory, apiKey: kind == .claude ? apiKey : nil)
        try plan.validate()
        return try await launcher.launch(plan, timeout: call.timeout)
    }
}
