import AgentCLI
import Foundation
import PageTools

@testable import WorkbenchCore

/// Where the two programs of the tools arm are, and the limits of its calls.
public struct PageEvalToolSetup: Sendable {
    public var claude: URL
    public var server: URL
    /// The server refuses the calls above this number with a tool error.
    public var toolCallCap = 12
    public var timeout = Duration.seconds(300)
    public var effort = "medium"
    /// The CLI stops a call that has cost this much. The CLI has no flag to cap turns.
    public var budgetUSD = 1.0

    public init(claude: URL, server: URL) {
        self.claude = claude
        self.server = server
    }
}

/// Arm two: the Claude CLI runs a loop over three read-only tools of a server made for the eval, and returns the same
/// operations by the same schema. The reply goes through the composer's own resolution, the gate and the checks.
enum PageEvalToolArm {
    static let serverName = "page"

    private static var allowedTools: [String] { PageToolService.toolNames.map { "mcp__\(serverName)__\($0)" } }

    /// The arguments of the CLI. `--tools ""` turns every built-in tool off; only the three tools of the one server
    /// are allowed; no settings, no session, no slash command, no other server.
    static func arguments(model: String, setup: PageEvalToolSetup, mcpConfig: URL) throws -> [String] {
        let tools = ["--tools", "", "--allowedTools", allowedTools.joined(separator: ",")]
        let isolation = ["--mcp-config", mcpConfig.path, "--strict-mcp-config", "--no-session-persistence"]
        let nothingLoaded = ["--setting-sources", "", "--disable-slash-commands", "--permission-mode", "dontAsk"]
        let prompt = [
            "--system-prompt", PageEvalToolInstructions.text, "--json-schema", try PageComposer.schema.jsonText,
        ]
        let call = ["-p", "--model", model, "--effort", setup.effort, "--output-format", "json"]
        return call + tools + isolation + nothingLoaded + ["--max-budget-usd", String(setup.budgetUSD)] + prompt
    }

    static func call(
        _ request: String, model: String, fixture: PageEvalFixture, setup: PageEvalToolSetup
    ) async throws -> PageEvalCall {
        let handles = PageHandles(page: fixture.start.page, items: fixture.facts)
        let gate = PageGate(catalog: PageCatalog(spec: fixture.machine.spec, items: fixture.facts))
        let folder = FileManager.default.temporaryDirectory.appending(path: "page-eval-tools-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let work = folder.appending(path: "cwd")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let log = folder.appending(path: "calls.jsonl")
        let config = try writeInputs(
            in: folder, fixture: toolFixture(of: fixture, handles: handles, blockCap: gate.blockCap), log: log,
            setup: setup)

        let clock = ContinuousClock()
        let begun = clock.now
        let output = try await PageEvalProcess.run(
            setup.claude, arguments: try arguments(model: model, setup: setup, mcpConfig: config),
            environment: environment(of: setup.claude), directory: work,
            stdin: input(request: request, spec: fixture.machine.spec), timeout: setup.timeout)
        var call = PageEvalCall()
        call.wallSeconds = begun.duration(to: clock.now).seconds
        try readLog(at: log, into: &call)
        let result = ClaudeResult.last(in: String(decoding: output.stdout, as: UTF8.self))
        let report = try? JSONDecoder().decode(CLIReport.self, from: output.stdout.lastLine)
        call.turns = report?.numTurns ?? 0
        call.permissionDenials = report?.permissionDenials.count ?? 0
        call.usage = result?.usage ?? Usage()
        guard let answer = result?.structuredAnswer, result?.isError == false else {
            call.failure =
                output.timedOut
                ? "timed out" : "no structured answer: \(result?.text ?? report?.subtype ?? "no result")"
            return call
        }
        do {
            let reply = try JSONDecoder().decode(PageComposer.Reply.self, from: Data(answer.utf8))
            call.reply = try? JSONDecoder().decode(JSONValue.self, from: Data(answer.utf8))
            call.unfetchedNames = unfetched(in: reply, returned: call.returnedHandles)
            call.proposal = try proposal(from: reply, handles: handles, gate: gate, fixture: fixture)
        } catch { call.failure = "\(error)" }
        return call
    }

    // MARK: inputs

    /// The input of the CLI: the request and the job only. The facts, the catalog and the page come by tool.
    static func input(request: String, spec: HelperSpec) -> String {
        "REQUEST\n\(request)\n\nYOUR JOB\n\(spec.brief)"
    }

    private static func writeInputs(
        in folder: URL, fixture: PageToolFixture, log: URL, setup: PageEvalToolSetup
    ) throws -> URL {
        let fixtureFile = folder.appending(path: "fixture.json")
        try JSONEncoder().encode(fixture).write(to: fixtureFile)
        let server: [String: Any] = [
            "command": setup.server.path, "args": [fixtureFile.path, log.path, String(setup.toolCallCap)],
        ]
        let config = folder.appending(path: "mcp.json")
        try JSONSerialization.data(withJSONObject: ["mcpServers": [serverName: server]]).write(to: config)
        return config
    }

    /// What the app's own call has: a short PATH, the person's home for the sign-in, and the kill switches. The
    /// person's settings, hooks and global instruction file are not loaded (checked in the report).
    private static func environment(of claude: URL) -> [String: String] {
        let inherited = ProcessInfo.processInfo.environment
        var environment = [
            "HOME": inherited["HOME"] ?? NSHomeDirectory(),
            "PATH": [claude.deletingLastPathComponent().path, "/usr/bin", "/bin"].joined(separator: ":"),
            "USER": inherited["USER"] ?? NSUserName(),
        ]
        for name in ["DISABLE_AUTOUPDATER", "DISABLE_TELEMETRY", "DISABLE_ERROR_REPORTING"] { environment[name] = "1" }
        return environment
    }

    /// The facts with their handles as the composer names them, the catalog, the columns and the blocks as the
    /// composer shows them.
    static func toolFixture(of fixture: PageEvalFixture, handles: PageHandles, blockCap: Int) -> PageToolFixture {
        let spec = fixture.machine.spec
        let page = fixture.start.page
        let words = Dictionary(fixture.start.notes.map { ($0.id, $0.text) }, uniquingKeysWith: { first, _ in first })
        let catalog = PageCatalog(spec: spec, items: fixture.facts)
        return PageToolFixture(
            facts: fixture.facts.compactMap { item in
                item.id.map { id in
                    PageToolFixture.Fact(
                        handle: handles.name(of: .fact(id)), day: item.day.description, quote: item.quote,
                        fields: spec.fields.map { .init(name: $0.name, value: item[$0.name]) })
                }
            },
            catalog: catalog.values.sorted { $0.key < $1.key }.map { .init(field: $0.key, values: $0.value.sorted()) },
            columns: catalog.columns.sorted(),
            blocks: page.order.map { block in
                switch block {
                case .note(let id): "\(handles.name(of: block)) person: \(words[id] ?? "")"
                case .machine(let id):
                    "\(handles.name(of: block)) machine: \(page.blocks[id].map { PageComposer.words(of: $0, handles) } ?? "")"
                }
            }, machineBlockCount: page.blocks.count, blockCap: blockCap)
    }

    // MARK: the reply

    /// The same steps as `PageComposer.compose` after the model call: every name turned back by the composer's own
    /// `operation(from:handles:)`, then the gate. The run row is a synthetic one: no recorded model made this reply.
    private static func proposal(
        from reply: PageComposer.Reply, handles: PageHandles, gate: PageGate, fixture: PageEvalFixture
    ) throws -> PageProposal {
        let resolved = reply.ops.map { PageComposer.operation(from: $0, handles: handles) }
        let (proposed, kept) = gate.apply(resolved.compactMap { try? $0.get() }, to: fixture.start.page)
        var allowed = kept[...]
        let verdicts = resolved.map { result in
            switch result {
            case .success: allowed.removeFirst()
            case .failure(let refusal): PageVerdict(operation: nil, refusal: refusal)
            }
        }
        let run = try fixture.store.beginRun(
            task: PageComposer.task, model: "synthetic", prompt: "tools arm", input: "no recorded call", kinds: [],
            window: [])
        try fixture.store.finishRun(run, model: "synthetic", usage: Usage(), reply: "")
        return PageProposal(note: reply.note, verdicts: verdicts, page: proposed, run: run)
    }

    /// The names the reply uses that no tool returned in this call. `R`, the request, is always known.
    static func unfetched(in reply: PageComposer.Reply, returned: Set<String>) -> Int {
        let used = reply.ops.flatMap { [$0.block, $0.after] + $0.cites }.filter { !$0.isEmpty }
        return Set(used).subtracting(returned).subtracting([PageHandles.request]).count
    }

    // MARK: the server's log

    private static func readLog(at url: URL, into call: inout PageEvalCall) throws {
        let entries = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map {
            try JSONDecoder().decode(PageToolLogEntry.self, from: Data($0.utf8))
        }
        call.toolCalls = entries.reduce(into: [:]) { $0[$1.tool, default: 0] += 1 }
        call.refusedToolCalls = entries.filter(\.refused).count
        call.toolErrors = entries.filter { $0.isError && !$0.refused }.count
        call.returnedHandles = Set(entries.flatMap(\.returnedHandles))
    }

    /// The parts of the CLI's result that `ClaudeResult` does not read.
    private struct CLIReport: Decodable {
        let numTurns: Int
        let subtype: String
        let permissionDenials: [JSONValue]

        private enum CodingKeys: String, CodingKey {
            case numTurns = "num_turns"
            case subtype
            case permissionDenials = "permission_denials"
        }
    }
}

extension Data {
    /// The last line that is not empty, which is where the CLI puts its result.
    fileprivate var lastLine: Data {
        split(separator: UInt8(ascii: "\n")).last.map { Data($0) } ?? self
    }
}
