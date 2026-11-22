import Foundation

public struct ProcessPlan: Sendable, Equatable {
    public var kind: AgentCLIKind
    public var executable: URL
    public var arguments: [String]
    public var environment: [String: String]
    public var stdin: String
    public var workDirectory: URL
    public var inputFiles: [String: String]
    public var answerFile: String?
    /// The founder's own Anthropic API key, chosen in Workbench, so the call is billed to it: the route Anthropic
    /// documents for programs (code.claude.com/docs/en/legal-and-compliance). In `-p` mode the CLI always uses a
    /// key that is present (code.claude.com/docs/en/authentication). Nil: the founder's own Claude sign-in.
    public var apiKey: String?
}

extension ProcessPlan {
    static let schemaFileName = "schema.json"
    static let answerFileName = "answer.json"

    private static let forbiddenNames: Set<String> = [
        "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "OPENAI_API_KEY", "CODEX_API_KEY",
    ]
    private static let forbiddenPrefixes = ["CLAUDE_CODE_", "CLAUDECODE", "ANTHROPIC_", "OPENAI_"]
    private static let killSwitches = ["DISABLE_AUTOUPDATER", "DISABLE_TELEMETRY", "DISABLE_ERROR_REPORTING"]
    private static let noServers = #"{"mcpServers":{}}"#
    private static let disabledCodexFeatures = ["shell_tool", "unified_exec", "view_image"]
    private static let codexSettings = ["web_search=\"disabled\""]

    static func isForbidden(variable name: String) -> Bool {
        forbiddenNames.contains(name) || forbiddenPrefixes.contains { name.hasPrefix($0) }
    }

    public static func make(
        call: AgentCall, kind: AgentCLIKind, executable: URL, environment inherited: [String: String],
        workDirectory: URL, apiKey: String? = nil
    ) -> ProcessPlan {
        var environment = environment(kind: kind, executable: executable, inherited: inherited)
        if let apiKey { environment[apiKeyVariable] = apiKey }
        return ProcessPlan(
            kind: kind, executable: executable,
            arguments: kind == .claude ? claudeArguments(call) : codexArguments(call, workDirectory: workDirectory),
            environment: environment, stdin: kind == .claude ? call.data : "\(call.systemPrompt)\n\n\(call.data)",
            workDirectory: workDirectory,
            inputFiles: kind == .codex ? [schemaFileName: call.schemaText] : [:],
            answerFile: kind == .codex ? answerFileName : nil, apiKey: apiKey)
    }

    static let apiKeyVariable = "ANTHROPIC_API_KEY"

    public func validate() throws {
        if let name = environment.keys.sorted().first(where: { name in
            Self.isForbidden(variable: name)
                && !(kind == .claude && name == Self.apiKeyVariable && apiKey?.isEmpty == false
                    && environment[name] == apiKey)
        }) {
            throw AgentCLIError.unsafePlan("environment holds \(name)")
        }
        switch kind {
        case .claude:
            try require(flags: ["--no-session-persistence", "--strict-mcp-config", "--disable-slash-commands"])
            try refuse(flags: ["--resume", "--allowedTools"])
            try require(values: [
                "--setting-sources": "", "--tools": "", "--permission-mode": "dontAsk", "--mcp-config": Self.noServers,
            ])
        case .codex:
            try require(flags: ["--ephemeral", "--ignore-user-config"])
            try require(values: ["--sandbox": "read-only"])
            let disabled = Set(values(after: "--disable"))
            if let enabled = Self.disabledCodexFeatures.first(where: { !disabled.contains($0) }) {
                throw AgentCLIError.unsafePlan("codex leaves \(enabled) on")
            }
            let settings = values(after: "--config")
            if let missing = Self.codexSettings.first(where: { !settings.contains($0) }) {
                throw AgentCLIError.unsafePlan("codex lacks \(missing)")
            }
            if let server = settings.first(where: { $0.hasPrefix("mcp_servers.") }) {
                throw AgentCLIError.unsafePlan("codex names a tool server: \(server)")
            }
        }
    }

    private func require(flags: [String]) throws {
        if let flag = flags.first(where: { !arguments.contains($0) }) { throw AgentCLIError.unsafePlan("no \(flag)") }
    }

    private func refuse(flags: [String]) throws {
        if let flag = flags.first(where: arguments.contains) {
            throw AgentCLIError.unsafePlan("\(flag) is not allowed")
        }
    }

    private func require(values: [String: String]) throws {
        for (flag, expected) in values.sorted(by: { $0.key < $1.key }) where self.values(after: flag) != [expected] {
            throw AgentCLIError.unsafePlan("\(flag) must be \"\(expected)\"")
        }
    }

    private func values(after flag: String) -> [String] {
        arguments.indices.dropLast().filter { arguments[$0] == flag }.map { arguments[$0 + 1] }
    }

    private static func claudeArguments(_ call: AgentCall) -> [String] {
        ["-p", "--output-format", "stream-json", "--verbose", "--model", call.model]
            + ["--effort", call.effort, "--setting-sources", "", "--disable-slash-commands"]
            + ["--no-session-persistence", "--strict-mcp-config", "--mcp-config", noServers]
            + ["--permission-mode", "dontAsk", "--tools", "", "--json-schema", call.schemaText]
            + ["--system-prompt", call.systemPrompt]
    }

    private static func codexArguments(_ call: AgentCall, workDirectory: URL) -> [String] {
        ["exec", "--ephemeral", "--skip-git-repo-check", "--ignore-user-config", "--sandbox", "read-only"]
            + disabledCodexFeatures.flatMap { ["--disable", $0] }
            + ["--cd", workDirectory.path, "--model", call.model]
            + (["model_reasoning_effort=\"\(call.effort)\""] + codexSettings).flatMap { ["--config", $0] }
            + ["--output-schema", workDirectory.appending(path: schemaFileName).path, "--json"]
            + ["--output-last-message", workDirectory.appending(path: answerFileName).path, "-"]
    }

    private static func environment(kind: AgentCLIKind, executable: URL, inherited: [String: String]) -> [String:
        String]
    {
        let path = [executable.deletingLastPathComponent().path, "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        var environment = ["HOME": inherited["HOME"] ?? NSHomeDirectory(), "PATH": path.joined(separator: ":")]
        environment["USER"] = inherited["USER"] ?? NSUserName()
        for name in ["LANG", "TMPDIR"] { environment[name] = inherited[name] }
        if kind == .claude { for name in killSwitches { environment[name] = "1" } }
        return environment
    }
}
