import Foundation

/// The exact process a call becomes. `validate` refuses any plan that could act, persist or read settings.
public struct ProcessPlan: Sendable, Equatable {
    public var kind: AgentCLIKind
    public var executable: URL
    public var arguments: [String]
    public var environment: [String: String]
    public var stdin: String
    /// The one folder every call runs in. Many calls share it, so each call names its files after `callID`.
    public var workDirectory: URL
    /// Makes the names of this call's files differ from the names of every other call in the folder.
    public var callID: String
    /// Files written into the work directory before the run: name and content.
    public var inputFiles: [String: String]
    /// A file in the work directory that holds the answer after the run.
    public var answerFile: String?
    /// The founder's own Anthropic API key, chosen in Workbench, so the call is billed to it: the route Anthropic
    /// documents for programs (code.claude.com/docs/en/legal-and-compliance). In `-p` mode the CLI always uses a
    /// key that is present (code.claude.com/docs/en/authentication). Nil: the founder's own Claude sign-in.
    public var apiKey: String?
    public var tools: AgentTools = .none
}

extension ProcessPlan {
    /// Every file this call puts in the work directory, besides the three the launcher spools.
    var fileNames: [String] { Array(inputFiles.keys) + [answerFile].compactMap { $0 } }

    static func schemaFileName(callID: String) -> String { "\(callID)-schema.json" }
    static func answerFileName(callID: String) -> String { "\(callID)-answer.json" }

    private static let forbiddenNames: Set<String> = [
        "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "OPENAI_API_KEY", "CODEX_API_KEY",
    ]
    private static let forbiddenPrefixes = ["CLAUDE_CODE_", "CLAUDECODE", "ANTHROPIC_", "OPENAI_"]
    private static let killSwitches = ["DISABLE_AUTOUPDATER", "DISABLE_TELEMETRY", "DISABLE_ERROR_REPORTING"]
    private static let noServers = #"{"mcpServers":{}}"#
    /// What every Claude call sets beside its flags. `--setting-sources ""` leaves auto memory on (the init event
    /// still names a memory folder; measured on CLI 2.1.331), so the call turns it off, and hooks with it.
    static let isolationSettings = #"{"autoMemoryEnabled":false,"disableAllHooks":true}"#
    private static let disabledCodexFeatures = ["shell_tool", "unified_exec", "view_image"]
    private static let codexSettings = ["web_search=\"disabled\""]

    static func isForbidden(variable name: String) -> Bool {
        forbiddenNames.contains(name) || forbiddenPrefixes.contains { name.hasPrefix($0) }
    }

    public static func make(
        call: AgentCall, kind: AgentCLIKind, executable: URL, environment inherited: [String: String],
        workDirectory: URL, callID: String = UUID().uuidString, apiKey: String? = nil
    ) -> ProcessPlan {
        var environment = environment(kind: kind, executable: executable, inherited: inherited)
        if let apiKey { environment[apiKeyVariable] = apiKey }
        return ProcessPlan(
            kind: kind, executable: executable,
            arguments: kind == .claude
                ? claudeArguments(call) : codexArguments(call, workDirectory: workDirectory, callID: callID),
            environment: environment, stdin: kind == .claude ? call.data : "\(call.systemPrompt)\n\n\(call.data)",
            workDirectory: workDirectory, callID: callID,
            inputFiles: kind == .codex ? [schemaFileName(callID: callID): call.schemaText] : [:],
            answerFile: kind == .codex ? answerFileName(callID: callID) : nil, apiKey: apiKey, tools: call.tools)
    }

    /// A question to the Claude CLI that makes no model call and sends no input.
    public enum ReaderQuery: Sendable {
        case authStatus, version

        var arguments: [String] {
            switch self {
            case .authStatus: ["auth", "status", "--json"]
            case .version: ["--version"]
            }
        }
    }

    public static func readerQuery(
        _ query: ReaderQuery, executable: URL, environment inherited: [String: String], workDirectory: URL
    ) -> ProcessPlan {
        ProcessPlan(
            kind: .claude, executable: executable, arguments: query.arguments,
            environment: environment(kind: .claude, executable: executable, inherited: inherited), stdin: "",
            workDirectory: workDirectory, callID: UUID().uuidString, inputFiles: [:], answerFile: nil, apiKey: nil)
    }

    static let apiKeyVariable = "ANTHROPIC_API_KEY"

    /// A credential from the founder's shell never reaches the CLI. The one exception is the key the founder chose
    /// in Workbench, for the Claude CLI, exactly as chosen.
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
            try refuse(flags: ["--resume"])
            try require(values: [
                "--setting-sources": "", "--permission-mode": "dontAsk", "--mcp-config": Self.noServers,
                "--settings": Self.isolationSettings,
            ])
            try requireToolSurface()
        case .codex:
            guard tools == .none else { throw AgentCLIError.unsafePlan("codex has no search variant") }
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

    /// No tool, or exactly the search tool both offered and allowed.
    private func requireToolSurface() throws {
        let offered = values(after: "--tools")
        let allowed = values(after: "--allowedTools")
        let noTool = offered == [""] && allowed.isEmpty
        let searchOnly = offered == [AgentTools.searchToolName] && allowed == [AgentTools.searchToolName]
        guard noTool || searchOnly else {
            throw AgentCLIError.unsafePlan("tools must be none or only \(AgentTools.searchToolName)")
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
            + ["--effort", call.effort, "--setting-sources", "", "--settings", isolationSettings]
            + ["--disable-slash-commands"]
            + ["--no-session-persistence", "--strict-mcp-config", "--mcp-config", noServers]
            + ["--permission-mode", "dontAsk"] + toolArguments(call.tools)
            + ["--json-schema", call.schemaText]
            + ["--system-prompt", call.systemPrompt]
    }

    private static func toolArguments(_ tools: AgentTools) -> [String] {
        switch tools {
        case .none: ["--tools", ""]
        case .webSearch: ["--tools", AgentTools.searchToolName, "--allowedTools", AgentTools.searchToolName]
        }
    }

    private static func codexArguments(_ call: AgentCall, workDirectory: URL, callID: String) -> [String] {
        ["exec", "--ephemeral", "--skip-git-repo-check", "--ignore-user-config", "--sandbox", "read-only"]
            + disabledCodexFeatures.flatMap { ["--disable", $0] }
            + ["--cd", workDirectory.path, "--model", call.model]
            + (["model_reasoning_effort=\"\(call.effort)\""] + codexSettings).flatMap { ["--config", $0] }
            + ["--output-schema", workDirectory.appending(path: schemaFileName(callID: callID)).path, "--json"]
            + ["--output-last-message", workDirectory.appending(path: answerFileName(callID: callID)).path, "-"]
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
