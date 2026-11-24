import Foundation

/// One program run to its end, with a time limit. The eval's own launcher for the tools arm: the app's `ProcessPlan`
/// refuses every tool server, so this arm cannot go through it.
enum PageEvalProcess {
    struct Output {
        var stdout: Data
        var timedOut: Bool
    }

    static func run(
        _ executable: URL, arguments: [String], environment: [String: String], directory: URL, stdin: String,
        timeout: Duration
    ) async throws -> Output {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                nonisolated(unsafe) let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                process.environment = environment
                process.currentDirectoryURL = directory
                let input = Pipe()
                let output = Pipe()
                process.standardInput = input
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                do { try process.run() } catch {
                    continuation.resume(throwing: error)
                    return
                }
                let stop = DispatchWorkItem { process.terminate() }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout.seconds, execute: stop)
                input.fileHandleForWriting.write(Data(stdin.utf8))
                try? input.fileHandleForWriting.close()
                let stdout = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                stop.cancel()
                continuation.resume(
                    returning: Output(stdout: stdout, timedOut: process.terminationReason == .uncaughtSignal))
            }
        }
    }
}
