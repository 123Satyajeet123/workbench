import Foundation
import Testing

@testable import AgentCLI

@Suite(.serialized) struct SystemProcessLauncherTests {
    private func plan(running executable: String, arguments: [String] = [], stdin: String = "") throws -> ProcessPlan {
        let directory = FileManager.default.temporaryDirectory.appending(path: "launcher-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var plan = makePlan()
        plan.executable = URL(fileURLWithPath: executable)
        plan.arguments = arguments
        plan.stdin = stdin
        plan.workDirectory = directory
        return plan
    }

    @Test func theLauncherFeedsStdinAndReturnsStdoutAndStatus() async throws {
        let plan = try plan(running: "/bin/cat", stdin: "hello")
        defer { try? FileManager.default.removeItem(at: plan.workDirectory) }
        let output = try await SystemProcessLauncher().launch(plan, timeout: .seconds(10))
        #expect(output == ProcessOutput(stdout: "hello", status: 0))
    }

    @Test func aProcessThatRunsPastTheTimeoutIsKilledAndReportsTimedOut() async throws {
        let plan = try plan(running: "/bin/sleep", arguments: ["30"])
        defer { try? FileManager.default.removeItem(at: plan.workDirectory) }
        let began = ContinuousClock.now
        await #expect(throws: AgentCLIError.timedOut) {
            try await SystemProcessLauncher().launch(plan, timeout: .milliseconds(300))
        }
        #expect(ContinuousClock.now - began < .seconds(10))
    }

    @Test func aCancelledLaunchEndsItsChildAtOnceAndAnUncancelledOneCompletes() async throws {
        let plan = try plan(running: "/bin/sleep", arguments: ["30"])
        defer { try? FileManager.default.removeItem(at: plan.workDirectory) }
        let began = ContinuousClock.now
        let launch = Task { try await SystemProcessLauncher().launch(plan, timeout: .seconds(60)) }
        try await Task.sleep(for: .milliseconds(300))
        launch.cancel()
        await #expect(throws: CancellationError.self) { try await launch.value }
        #expect(ContinuousClock.now - began < .seconds(5))
        #expect(RunningChildren.isEmpty)

        let quick = try self.plan(running: "/bin/sleep", arguments: ["0.2"])
        defer { try? FileManager.default.removeItem(at: quick.workDirectory) }
        let output = try await SystemProcessLauncher().launch(quick, timeout: .seconds(10))
        #expect(output.status == 0)
    }

    @Test func aLaunchThatIsAlreadyCancelledNeverStartsTheChild() async throws {
        let plan = try plan(running: "/bin/sleep", arguments: ["30"])
        defer { try? FileManager.default.removeItem(at: plan.workDirectory) }
        let launch = Task {
            while !Task.isCancelled { await Task.yield() }
            return try await SystemProcessLauncher().launch(plan, timeout: .seconds(60))
        }
        launch.cancel()
        await #expect(throws: CancellationError.self) { try await launch.value }
        #expect(RunningChildren.isEmpty)
    }

    @Test func terminateAllEndsEveryRunningChildAndAnIdleCallReturnsAtOnce() async throws {
        RunningChildren.terminateAll()
        let plan = try plan(running: "/bin/sleep", arguments: ["30"])
        defer { try? FileManager.default.removeItem(at: plan.workDirectory) }
        let launch = Task { try await SystemProcessLauncher().launch(plan, timeout: .seconds(60)) }
        try await Task.sleep(for: .milliseconds(300))
        #expect(!RunningChildren.isEmpty)
        let began = ContinuousClock.now
        RunningChildren.terminateAll()
        #expect(ContinuousClock.now - began < .seconds(3))
        let output = try await launch.value
        #expect(output.status != 0)
        #expect(RunningChildren.isEmpty)
    }
}
