import Foundation
import Testing
import WorkbenchCore

@testable import AgentCLI

/// The CLI keys its prompt cache on the work folder, so every call must run in the one fixed folder.
@Suite struct FixedWorkFolderTests {
    private let files = FileManager.default

    private func makeFolder() throws -> URL {
        let folder = files.temporaryDirectory.appending(path: "d5-\(UUID().uuidString)")
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// A fake CLI. It lists its work folder into `log` while it runs, then answers.
    private func fakeCLI(_ kind: AgentCLIKind, in folder: URL, log: URL) throws -> URL {
        let script = folder.appending(path: kind.rawValue)
        let body: String
        switch kind {
        case .claude:
            body = #"""
                ls >> "\#(log.path)"; echo "cwd=$(pwd -P)" >> "\#(log.path)"; sleep 0.4
                echo '{"type":"result","is_error":false,"structured_output":{"label":"yes"}}'
                """#
        case .codex:
            body = #"""
                while [ $# -gt 0 ]; do [ "$1" = "--output-last-message" ] && out="$2"; shift; done
                echo '{"label":"codex"}' > "$out"; echo '{"type":"turn.completed","usage":{}}'
                """#
        }
        try "#!/bin/sh\n\(body)\n".write(to: script, atomically: true, encoding: .utf8)
        try files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    private func runner(_ kind: AgentCLIKind, tool: URL, workDirectory: URL) -> AgentRunner {
        AgentRunner(
            kind: kind, model: "m", effort: "low", timeout: .seconds(20), executable: tool,
            environment: ["HOME": NSHomeDirectory()], workDirectory: workDirectory)
    }

    private static func ask(_ runner: AgentRunner) async throws -> String {
        try await runner.generate(Verdict.self, schema: Verdict.schema, instructions: "", input: "x").value.label
    }

    private static func realPath(_ url: URL) -> String { String(cString: realpath(url.path, nil)) }

    private func loggedLines(_ log: URL) throws -> [String] {
        try String(contentsOf: log, encoding: .utf8).split(separator: "\n").map(String.init)
    }

    private func contents(_ folder: URL) throws -> [String] { try files.contentsOfDirectory(atPath: folder.path) }

    @Test func everyCallRunsInTheOneFixedFolderAndLeavesItEmpty() async throws {
        let scratch = try makeFolder()
        defer { try? files.removeItem(at: scratch) }
        let log = scratch.appending(path: "log.txt")
        let work = scratch.appending(path: "work")
        let runner = runner(.claude, tool: try fakeCLI(.claude, in: scratch, log: log), workDirectory: work)
        for _ in 1...3 {
            #expect(try await Self.ask(runner) == "yes")
            #expect(try contents(work).isEmpty, "the folder is empty between calls")
        }
        let folders = Set(try loggedLines(log).filter { $0.hasPrefix("cwd=") })
        #expect(folders == ["cwd=\(Self.realPath(work))"])
    }

    @Test func theFixedFolderIsPrivate() async throws {
        let scratch = try makeFolder()
        defer { try? files.removeItem(at: scratch) }
        let work = scratch.appending(path: "work")
        let log = scratch.appending(path: "log.txt")
        _ = try await Self.ask(runner(.claude, tool: try fakeCLI(.claude, in: scratch, log: log), workDirectory: work))
        let mode = try files.attributesOfItem(atPath: work.path)[.posixPermissions] as? Int
        #expect(mode == 0o700)
    }

    @Test func twoCallsAtOnceUseDistinctFileNamesAndBothSucceed() async throws {
        let scratch = try makeFolder()
        defer { try? files.removeItem(at: scratch) }
        let log = scratch.appending(path: "log.txt")
        let work = scratch.appending(path: "work")
        let runner = runner(.claude, tool: try fakeCLI(.claude, in: scratch, log: log), workDirectory: work)
        async let first = Self.ask(runner)
        async let second = Self.ask(runner)
        #expect(try await [first, second] == ["yes", "yes"])
        let names = Set(try loggedLines(log).filter { !$0.hasPrefix("cwd=") })
        #expect(names.count == 6, "each call has its own three spool files")
        #expect(try contents(work).isEmpty)
    }

    @Test func aCodexCallFindsItsAnswerFileInTheFixedFolderAndRemovesIt() async throws {
        let scratch = try makeFolder()
        defer { try? files.removeItem(at: scratch) }
        let work = scratch.appending(path: "work")
        let tool = try fakeCLI(.codex, in: scratch, log: scratch.appending(path: "log.txt"))
        #expect(try await Self.ask(runner(.codex, tool: tool, workDirectory: work)) == "codex")
        #expect(try contents(work).isEmpty)
    }
}
