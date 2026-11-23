import Foundation
import WorkbenchCore

/// Reads the state of the Claude command-line tool: installed, which version, signed in how. It makes no model call.
public struct ReaderProbe: Sendable {
    private let launcher: any ProcessLauncher
    private let environment: [String: String]
    private let home: URL
    private let workDirectory: URL
    private let timeout: Duration

    public init(
        launcher: any ProcessLauncher = SystemProcessLauncher(),
        environment: [String: String] = ProcessInfo.processInfo.environment, home: URL = .homeDirectory,
        workDirectory: URL,
        timeout: Duration = .seconds(10)
    ) {
        self.launcher = launcher
        self.environment = environment
        self.home = home
        self.workDirectory = workDirectory
        self.timeout = timeout
    }

    public func status() async -> ReaderStatus {
        guard let executable = AgentCLIKind.claude.installed(environment: environment, home: home) else {
            return .notInstalled
        }
        let signIn = await output(of: .authStatus, executable: executable)
        let version = await output(of: .version, executable: executable)
        return ReaderStatus.parse(
            authStatus: Data(signIn.utf8), installedAt: executable, version: ReaderStatus.version(from: version))
    }

    private func output(of query: ProcessPlan.ReaderQuery, executable: URL) async -> String {
        let plan = ProcessPlan.readerQuery(
            query, executable: executable, environment: environment, workDirectory: workDirectory)
        do {
            try AgentRunner.prepare(workDirectory)
            return try await launcher.launch(plan, timeout: timeout).stdout
        } catch {
            return ""
        }
    }
}
