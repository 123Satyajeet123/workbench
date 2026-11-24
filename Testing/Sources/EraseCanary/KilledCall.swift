import AgentCLI
import Foundation

/// A model call that the app does not live to finish: the launcher spools the call's input to a file in the agent work
/// folder and removes it when the call ends, so a crash or a kill leaves it. This runs the real launcher in a child
/// process over a program that never answers, and kills the child with SIGKILL, as a crash would.
enum KilledCall {
    static let flag = "--hold-a-call"

    /// The child: starts a call whose input is `prompt`, and waits for an answer that never comes.
    static func hold(in workDirectory: URL, program: URL, prompt: String) async throws {
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        let call = AgentCall(
            prompt: prompt, instructions: "Read it.", schemaText: "{}", model: "example", effort: "low",
            timeout: .seconds(300))
        let plan = ProcessPlan.make(
            call: call, kind: .claude, executable: program, environment: [:], workDirectory: workDirectory)
        _ = try await SystemProcessLauncher().launch(plan, timeout: .seconds(300))
    }

    /// The parent: leaves the input of a call that held `prompt` in `workDirectory`.
    static func leaveInput(of prompt: String, in workDirectory: URL) throws {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "killed-call-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let processFile = scratch.appending(path: "pid")
        let program = scratch.appending(path: "never-answers")
        try "#!/bin/sh\necho $$ > '\(processFile.path)'\nexec sleep 300\n".write(
            to: program, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: program.path)
        let child = Process()
        child.executableURL = Bundle.main.executableURL
        child.arguments = [flag, workDirectory.path, program.path, prompt]
        try child.run()
        try waitUntil { FileManager.default.fileExists(atPath: processFile.path) }
        let programProcess = try Int32(
            String(contentsOf: processFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))
        kill(child.processIdentifier, SIGKILL)
        if let programProcess { kill(programProcess, SIGKILL) }
        child.waitUntilExit()
    }

    private static func waitUntil(_ holds: () -> Bool) throws {
        for _ in 0..<200 where !holds() { Thread.sleep(forTimeInterval: 0.05) }
        guard holds() else { throw SceneError("the child process never started its call") }
    }
}
