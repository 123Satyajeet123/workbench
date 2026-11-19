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

    @Test func aProcessThatRunsPastTheTimeoutIsKilledAndReportsTimedOut() async throws {
        let plan = try plan(running: "/bin/sleep", arguments: ["30"])
        defer { try? FileManager.default.removeItem(at: plan.workDirectory) }
        let began = ContinuousClock.now
        await #expect(throws: AgentCLIError.timedOut) {
            try await SystemProcessLauncher().launch(plan, timeout: .milliseconds(300))
        }
        #expect(ContinuousClock.now - began < .seconds(10))
    }

}
