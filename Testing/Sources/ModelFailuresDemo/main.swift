import AgentCLI
import Foundation
import SQLite3
import Synchronization

@testable import WorkbenchCore
@testable import WorkbenchUI

// Shows the gates of step D6 on made-up data. A fake launcher answers with recorded stream-json output, each store is
// a scratch folder, the clock is a variable, and nothing touches the network or ~/Library/Application Support/Workbench.
// Usage: model-failures
setvbuf(stdout, nil, _IOLBF, 0)
var failures = 0

func check(_ condition: Bool, _ words: String) {
    if !condition { failures += 1 }
    print("  \(condition ? "yes" : "NO ") \(words)")
}

func gate(_ name: String, _ body: () async throws -> Void) async {
    print("\n\(name)")
    do { try await body() } catch {
        failures += 1
        print("  NO  stopped: \(error)")
    }
}

let scratch = FileManager.default.temporaryDirectory.appending(path: "model-failures-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: scratch) }
let start = Date(timeIntervalSince1970: 1_800_000_000)

nonisolated final class Clock: Sendable {
    private let now = Mutex(start)
    var date: Date { now.withLock { $0 } }
    func advance(to date: Date) { now.withLock { $0 = date } }
}

nonisolated enum Step: Sendable {
    case output(String)
    case failing(any Error)
}

/// Plays the recorded steps in order, and the last one again when they run out.
nonisolated final class ScriptedLauncher: ProcessLauncher, Sendable {
    private let steps: Mutex<[Step]>
    private let count = Mutex(0)
    init(_ steps: [Step]) { self.steps = Mutex(steps) }
    var launches: Int { count.withLock { $0 } }

    func launch(_ plan: ProcessPlan, timeout: Duration) async throws -> ProcessOutput {
        count.withLock { $0 += 1 }
        let step = steps.withLock { $0.count > 1 ? $0.removeFirst() : $0[0] }
        switch step {
        case .output(let text): return ProcessOutput(stdout: text)
        case .failing(let error): throw error
        }
    }
}

func limitEvent(resetsAt: Date?) -> String {
    let reset = resetsAt.map { #","resetsAt":\#(Int($0.timeIntervalSince1970))"# } ?? ""
    return
        #"{"type":"rate_limit_event","rate_limit_info":{"status":"rejected","rateLimitType":"seven_day","utilization":1.0\#(reset)}}"#
}

func errorResult(_ words: String) -> String {
    #"{"type":"result","subtype":"success","is_error":true,"result":"\#(words)"}"#
}

let answered = #"{"type":"result","is_error":false,"structured_output":{"label":"yes"}}"#

nonisolated struct Verdict: Decodable, Sendable { let label: String }

nonisolated final class Waits: Sendable {
    private let list = Mutex<[Duration]>([])
    func add(_ duration: Duration) { list.withLock { $0.append(duration) } }
    var all: [Duration] { list.withLock { $0 } }
}

struct World {
    let store: Store
    let clock: Clock
    let launcher: ScriptedLauncher
    let waits: Waits
    let model: RecordedModel

    init(
        _ name: String, _ steps: [Step], kind: AgentCLIKind = .claude, installed: Bool = true,
        requiresAPIKey: Bool = false, tools: AgentTools = .none, confirmed: Bool = true
    ) throws {
        clock = Clock()
        let clock = clock
        store = try Store(directory: scratch.appending(path: name), clock: { clock.date })
        if confirmed { try store.confirmModelTerms() }
        launcher = ScriptedLauncher(steps)
        let waits = Waits()
        self.waits = waits
        var policy = FailurePolicy()
        policy.wait = { waits.add($0) }
        policy.jitter = { 0.5 }
        var runner = AgentRunner(
            kind: kind, model: "opus", effort: "low", timeout: .seconds(5), launcher: launcher,
            executable: URL(filePath: "/opt/fake/\(kind.rawValue)"),
            environment: ["PATH": "/nonexistent", "HOME": scratch.path], requiresAPIKey: requiresAPIKey,
            tools: tools, workDirectory: scratch.appending(path: "work"))
        if !installed { runner.executable = nil }
        model = RecordedModel(runner, store: store, policy: policy)
    }

    @discardableResult
    func ask(task: String = "demo") async -> String {
        do {
            _ = try await model.generate(
                Verdict.self, schema: .object([.init("label", .string)]), task: task, instructions: "Say yes.",
                input: "made-up input", holding: [])
            return "answered"
        } catch { return error.localizedDescription }
    }

    var runs: [Run] { (try? store.queries.runs().reversed()) ?? [] }
    func shape(_ run: Run) -> String { "\(run.outcome.rawValue)/\(run.failure?.rawValue ?? "-")" }
    var shapes: [String] { runs.map(shape) }
}

await gate("G1 each failure kind, from a fake CLI output") {
    let limited = try World("limit", [.output(limitEvent(resetsAt: start + 7200) + "\n" + errorResult("boom"))])
    await limited.ask()
    check(limited.shapes == ["failed/limit"], "rate_limit_event rejected, then a failed result: \(limited.shapes)")

    let trap = try World("trap", [.output(errorResult("You've hit your weekly limit · resets Dec 1"))])
    await trap.ask()
    check(trap.shapes == ["failed/other"], "the words 'weekly limit' with no event: \(trap.shapes)")

    let timedOut = try World("timeout", [.failing(AgentCLIError.timedOut)])
    await timedOut.ask()
    check(
        timedOut.runs.first?.failure == .timedOut, "launcher time-out (then its one retry, see G3): \(timedOut.shapes)")

    let missing = try World("missing", [.output(answered)], installed: false)
    await missing.ask()
    check(
        missing.shapes == ["failed/notInstalled"] && missing.launcher.launches == 0,
        "CLI not installed: \(missing.shapes)")

    let noKey = try World("nokey", [.output(answered)], requiresAPIKey: true)
    await noKey.ask()
    check(noKey.shapes == ["failed/noAPIKey"], "billing is a key and none is saved: \(noKey.shapes)")

    let unsafe = try World("unsafe", [.output(answered)], kind: .codex, tools: .webSearch)
    await unsafe.ask()
    check(unsafe.shapes == ["failed/unsafePlan"], "a plan the checks refuse: \(unsafe.shapes)")

    let other = try World("other", [.output(errorResult("boom"))])
    await other.ask()
    check(other.shapes == ["failed/other"], "a failed result and no limit event: \(other.shapes)")

    let cancelled = try World("cancelled", [.failing(CancellationError())])
    await cancelled.ask()
    let run = cancelled.runs.first
    check(
        cancelled.shapes == ["cancelled/-"] && run?.error == nil && cancelled.launcher.launches == 1,
        "cancelled: no failure, no error text: \(cancelled.shapes)")

    let refused = try World("refused", [.output(answered)], confirmed: false)
    let words = await refused.ask()
    check(
        refused.runs.isEmpty && refused.launcher.launches == 0,
        "terms not confirmed: no run row, no call. \(words.prefix(40))...")

    let fine = try World("fine", [.output(answered)])
    check(await fine.ask() == "answered" && fine.shapes == ["done/-"], "an answer: \(fine.shapes)")
}

await gate("G2 a limit pauses every later call until the reset, then calls run") {
    let world = try World(
        "pause", [.output(limitEvent(resetsAt: start + 7200) + "\n" + errorResult("boom")), .output(answered)])
    await world.ask(task: "day.timeline")
    check(
        world.store.pausedUntil(plan: "claude") == start + 7200,
        "the pause is in the store, until the reset the CLI gave")
    world.clock.advance(to: start + 600)
    let again = await world.ask(task: "team.ledger")
    let third = await world.ask(task: "mochi.summary")
    check(
        world.launcher.launches == 1 && world.runs.count == 1,
        "two more machines during the pause: no call, no run row (\(world.launcher.launches) launch, \(world.runs.count) run)"
    )
    check(again == third && again.contains("at its limit"), "one reason, same for both: \(again)")
    world.clock.advance(to: start + 7201)
    check(
        await world.ask() == "answered" && world.shapes == ["failed/limit", "done/-"],
        "after the reset: runs, \(world.shapes)")

    let noReset = try World("pause-no-reset", [.output(limitEvent(resetsAt: nil) + "\n" + errorResult("boom"))])
    await noReset.ask()
    check(noReset.store.pausedUntil(plan: "claude") == start + 3600, "no resetsAt: one hour")

    let other = try World("pause-none", [.output(errorResult("boom"))])
    await other.ask()
    check(other.store.pausedUntil(plan: "claude") == nil, "a failure that is not a limit: no pause")

    let codex = try World("pause-codex", [.output(answered)], kind: .codex)
    try codex.store.pauseModel(plan: "claude", until: start + 7200)
    await codex.ask()
    check(codex.launcher.launches == 1, "a pause of the Claude plan does not stop Codex: it launched")
}

await gate("G3 a time-out is tried once more, after a jittered wait, and no more") {
    let always = try World("retry-always", [.failing(AgentCLIError.timedOut)])
    await always.ask()
    check(
        always.launcher.launches == 2 && always.shapes == ["failed/timedOut", "failed/timedOut"],
        "always times out: \(always.launcher.launches) launches, \(always.shapes)")
    check(always.waits.all == [.seconds(5)], "one wait, jitter 0.5 of a 10 s window: \(always.waits.all)")

    let second = try World("retry-second", [.failing(AgentCLIError.timedOut), .output(answered)])
    check(
        await second.ask() == "answered" && second.shapes == ["failed/timedOut", "done/-"],
        "second try answers: \(second.shapes)")

    let other = try World("retry-other", [.output(errorResult("boom"))])
    await other.ask()
    check(other.launcher.launches == 1 && other.waits.all.isEmpty, "another failure: no retry, no wait")

    let cancelled = try World("retry-cancelled", [.failing(CancellationError())])
    await cancelled.ask()
    check(cancelled.launcher.launches == 1, "cancelled: no retry")
}

await gate("G4 a cancelled run is not counted in quality, cost or the usage report") {
    let world = try World(
        "quality", [.output(answered), .failing(CancellationError()), .output(errorResult("boom")), .output(answered)])
    await world.ask()
    let one = try world.store.queries.quality().first?.runs
    await world.ask()
    await world.ask()
    let afterOthers = try world.store.queries.quality().first?.runs
    check(
        one == 1 && afterOthers == 1,
        "quality: 1 done run, still 1 after a cancelled and a failed run: \(String(describing: afterOthers))")
    await world.ask()
    check(try world.store.queries.quality().first?.runs == 2, "a second done run: 2")
    let report = UsageReport(runs: try world.store.queries.runs(), days: 1, now: world.clock.date, name: { $0 })
    check(report.calls == 3, "usage report: 3 calls (2 done, 1 failed; the cancelled one is left out), \(world.shapes)")
}

func execute(_ sql: String, on database: OpaquePointer?) {
    if sqlite3_exec(database, sql, nil, nil, nil) != SQLITE_OK { fatalError(String(cString: sqlite3_errmsg(database))) }
}

await gate("Old rows stay, and are not reclassified by their words") {
    let folder = scratch.appending(path: "old")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var database: OpaquePointer?
    sqlite3_open(folder.appending(path: "workbench.sqlite").path, &database)
    let earlier = Schema.steps.dropLast()
    for statement in earlier.joined() { execute(statement, on: database) }
    execute("PRAGMA user_version = \(earlier.count)", on: database)
    let insert =
        "INSERT INTO run(task, model, prompt, input_bytes, input_sha, started_at, ended_at, outcome, error) VALUES "
    execute(
        insert
            + "('mochi.summary','claude opus','p',1,'s','2026-11-20T10:00:00Z','2026-11-20T10:01:00Z','failed','Swift.CancellationError'),"
            + "('team.ledger','claude opus','p',1,'s','2026-11-20T11:00:00Z','2026-11-20T11:01:00Z','failed','You have hit your weekly limit'),"
            + "('day.timeline','claude opus','p',1,'s','2026-11-20T12:00:00Z','2026-11-20T12:01:00Z','done',NULL)",
        on: database)
    sqlite3_close(database)
    let store = try Store(directory: folder)
    let old = try store.queries.runs().reversed().map {
        "\($0.outcome.rawValue)/\($0.failure?.rawValue ?? "-")/\($0.error ?? "-")"
    }
    check(
        old == ["failed/other/Swift.CancellationError", "failed/other/You have hit your weekly limit", "done/-/-"],
        "3 old rows kept; a failed one with a cancellation error stays failed/other: \(old)")
}

print(failures == 0 ? "\nAll gates held." : "\n\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
