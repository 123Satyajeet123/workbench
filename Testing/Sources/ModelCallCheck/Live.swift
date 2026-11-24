import Foundation

@testable import AgentCLI

/// One real run of the installed Claude CLI with no tools: what the model was offered and what loaded beside our
/// flags. It sends only made-up words to the model.
enum Live {
    struct Seen {
        var initEvent: [String: Any] = [:]
        var hookEvents = 0
        var word = ""
    }

    static func run() async {
        guard let claude = AgentCLIKind.claude.installed() else {
            failures += 1
            print("\nLIVE  NO  the Claude CLI is not installed")
            return
        }
        let folder = FileManager.default.temporaryDirectory.appending(path: "model-call-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let work = folder.appending(path: "work")
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        print("\nL2 a real run with no tools: the model is offered none, and nothing of the person's loads")
        guard let plain = await events(of: .none, claude: claude, work: work) else { return }
        check(Set(plain.initEvent["tools"] as? [String] ?? []) == ["StructuredOutput"], "only the answer tool")
        check((plain.initEvent["mcp_servers"] as? [[String: Any]] ?? []).isEmpty, "no server")
        check(plain.initEvent["memory_paths"] == nil, "no auto memory folder is named")
        check(plain.hookEvents == 0, "no hook ran (\(plain.hookEvents) hook events)")
    }

    static func events(of tools: AgentTools, claude: URL, work: URL) async -> Seen? {
        let plan = ProcessPlan.make(
            call: call(tools), kind: .claude, executable: claude,
            environment: ProcessInfo.processInfo.environment, workDirectory: work)
        do {
            try plan.validate()
            let output = try await SystemProcessLauncher().launch(plan, timeout: .seconds(120))
            var seen = Seen()
            for line in output.stdout.split(separator: "\n") {
                guard let event = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                    continue
                }
                let subtype = event["subtype"] as? String ?? ""
                if event["type"] as? String == "system", subtype == "init" { seen.initEvent = event }
                if subtype.contains("hook") { seen.hookEvents += 1 }
                if event["type"] as? String == "result" {
                    seen.word = (event["structured_output"] as? [String: Any])?["word"] as? String ?? ""
                }
            }
            if seen.initEvent.isEmpty {
                failures += 1
                print("  NO  the run gave no init event: exit \(output.status) \(output.stderr.prefix(200))")
                return nil
            }
            return seen
        } catch {
            failures += 1
            print("  NO  the run stopped: \(error)")
            return nil
        }
    }
}
