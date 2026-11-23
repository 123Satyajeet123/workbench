// Adapted from Sentient OS macOS (AGPL-3.0).
import Foundation
import Synchronization

public struct ProcessOutput: Sendable, Equatable {
    public var stdout: String
    public var stderr: String
    public var status: Int32
    /// The text of the plan's answer file, when it has one and the run wrote it.
    public var answerFile: String?

    public init(stdout: String, stderr: String = "", status: Int32 = 0, answerFile: String? = nil) {
        self.stdout = stdout
        self.stderr = stderr
        self.status = status
        self.answerFile = answerFile
    }
}

public protocol ProcessLauncher: Sendable {
    func launch(_ plan: ProcessPlan, timeout: Duration) async throws -> ProcessOutput
}

public enum RunningChildren {
    private static let killGrace: Duration = .seconds(5)
    private static let pids = Mutex<Set<Int32>>([])

    static func add(_ pid: Int32) { pids.withLock { _ = $0.insert(pid) } }

    static func remove(_ pid: Int32) { pids.withLock { _ = $0.remove(pid) } }

    static var isEmpty: Bool { pids.withLock { $0.isEmpty } }

    private static func isRunning(_ pid: Int32) -> Bool { pids.withLock { $0.contains(pid) } }

    /// SIGTERM now, and SIGKILL after the grace if the child is still there.
    static func terminate(_ pid: Int32, grace: Duration = killGrace) async {
        kill(pid, SIGTERM)
        try? await Task.sleep(for: grace, clock: ContinuousClock())
        if isRunning(pid) { kill(pid, SIGKILL) }
    }

    /// For app quit: ends every running child before it returns, or after the grace at most.
    public static func terminateAll(grace: Duration = .seconds(2)) {
        let running = pids.withLock { $0 }
        for pid in running { kill(pid, SIGTERM) }
        let deadline = ContinuousClock.now + grace
        while ContinuousClock.now < deadline, !pids.withLock({ $0.isEmpty }) { usleep(20_000) }
        for pid in pids.withLock({ $0 }) { kill(pid, SIGKILL) }
    }
}

public struct SystemProcessLauncher: ProcessLauncher {
    public init() {}

    public func launch(_ plan: ProcessPlan, timeout: Duration) async throws -> ProcessOutput {
        let directory = plan.workDirectory
        let stdinFile = directory.appending(path: "\(plan.callID)-stdin.txt")
        let stdoutFile = directory.appending(path: "\(plan.callID)-stdout.txt")
        let stderrFile = directory.appending(path: "\(plan.callID)-stderr.txt")
        let callFiles = [stdinFile, stdoutFile, stderrFile] + plan.fileNames.map { directory.appending(path: $0) }
        defer { for file in callFiles { try? FileManager.default.removeItem(at: file) } }
        try Data(plan.stdin.utf8).write(to: stdinFile)
        for (name, content) in plan.inputFiles { try Data(content.utf8).write(to: directory.appending(path: name)) }
        FileManager.default.createFile(atPath: stdoutFile.path, contents: nil)
        FileManager.default.createFile(atPath: stderrFile.path, contents: nil)

        let process = Process()
        process.executableURL = plan.executable
        process.arguments = plan.arguments
        process.environment = plan.environment
        process.currentDirectoryURL = directory
        process.standardInput = try FileHandle(forReadingFrom: stdinFile)
        process.standardOutput = try FileHandle(forWritingTo: stdoutFile)
        process.standardError = try FileHandle(forWritingTo: stderrFile)

        try Task.checkCancellation()
        let timedOut = Mutex(false)
        let started = Mutex<Int32?>(nil)
        var watchdog: Task<Void, any Error>?
        let status = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, any Error>) in
                process.terminationHandler = {
                    RunningChildren.remove($0.processIdentifier)
                    continuation.resume(returning: $0.terminationStatus)
                }
                do { try process.run() } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                    return
                }
                let pid = process.processIdentifier
                RunningChildren.add(pid)
                started.withLock { $0 = pid }
                if Task.isCancelled { Task { await RunningChildren.terminate(pid) } }
                watchdog = Task {
                    try await Task.sleep(for: timeout, clock: ContinuousClock())
                    timedOut.withLock { $0 = true }
                    await RunningChildren.terminate(pid)
                }
            }
        } onCancel: {
            if let pid = started.withLock({ $0 }) { Task { await RunningChildren.terminate(pid) } }
        }
        watchdog?.cancel()
        if timedOut.withLock({ $0 }) { throw AgentCLIError.timedOut }
        try Task.checkCancellation()

        return ProcessOutput(
            stdout: try String(contentsOf: stdoutFile, encoding: .utf8),
            stderr: try String(contentsOf: stderrFile, encoding: .utf8),
            status: status,
            answerFile: plan.answerFile.flatMap {
                try? String(contentsOf: directory.appending(path: $0), encoding: .utf8)
            }
        )
    }
}
