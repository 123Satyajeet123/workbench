import Foundation

/// The command-line agents Workbench can run a model through. Each uses the founder's own plan and login.
public enum AgentCLIKind: String, Sendable, CaseIterable, Codable {
    case claude, codex

    /// The installed CLI: the first match on the PATH, then in the folders the installers use. An app opened from the
    /// Dock gets a short PATH, so the folders matter.
    public func installed(
        environment: [String: String] = ProcessInfo.processInfo.environment, home: URL = .homeDirectory,
        isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)
    ) -> URL? {
        let path = (environment["PATH"] ?? "").split(separator: ":").map { URL(fileURLWithPath: String($0)) }
        let folders =
            [".local/bin", ".claude/local", ".npm-global/bin", ".bun/bin"].map { home.appending(path: $0) }
            + ["/opt/homebrew/bin", "/usr/local/bin"].map { URL(fileURLWithPath: $0) }
        return (path + folders).map { $0.appending(path: rawValue) }.first { isExecutable($0.path) }
    }
}

/// One call to an agent CLI: a prompt, the schema its answer must fit, no tools, no settings, no session.
public struct AgentCall: Sendable {
    public var prompt: String
    public var instructions: String
    public var schemaText: String
    public var model: String
    public var effort: String
    public var timeout: Duration

    public init(
        prompt: String, instructions: String, schemaText: String, model: String, effort: String, timeout: Duration
    ) {
        self.prompt = prompt
        self.instructions = instructions
        self.schemaText = schemaText
        self.model = model
        self.effort = effort
        self.timeout = timeout
    }

    /// The text that leaves the Mac on stdin.
    public var promptText: String { instructions.isEmpty ? prompt : "\(instructions)\n\n\(prompt)" }
}

public enum AgentCLIError: Error, Equatable {
    case notInstalled(AgentCLIKind)
    case unsafePlan(String)
    case timedOut
}
