import AgentCLI
import Foundation
import Kernel
import Lines
import Synchronization
import WorkbenchCore

// Checks the three bug fixes of step A0 on synthetic data: no model call, no network, no live store. Each store is a
// scratch folder. Prints ALL OK, or the first failing line, and exits 1.
// Usage: bugfix-check

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

nonisolated(unsafe) var failed: String?

func expect(_ claim: String, _ holds: Bool) {
    print("  \(holds ? "yes" : "NO ") \(claim)")
    if !holds, failed == nil { failed = claim }
}

func heading(_ text: String) { print("\n\(text)") }

let scratch = FileManager.default.temporaryDirectory.appending(path: "bugfix-check-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: scratch) }
let start = Date(timeIntervalSince1970: 1_795_000_000)
let chat = "111@g.us"
let member = "91@s.whatsapp.net"

// MARK: A split day

/// Answers every call with no items, and fails the calls whose number is in `failing`.
final class PartsModel: StructuredModel, Sendable {
    let name = "parts"
    let inputs = Mutex<[String]>([])
    let failing: Set<Int>

    init(failing: Set<Int> = []) { self.failing = failing }

    func generate<T: Decodable & Sendable>(_ type: T.Type, schema: JSONSchema, instructions: String, input: String)
        async throws -> ModelAnswer<T>
    {
        let call = inputs.withLock { calls -> Int in
            calls.append(input)
            return calls.count
        }
        if failing.contains(call) { throw StructuredModelError.unavailable("fake failure in call \(call)") }
        let reply = #"{"items":[]}"#
        return ModelAnswer(
            value: try JSONDecoder().decode(T.self, from: Data(reply.utf8)), model: name, usage: Usage(),
            reply: reply)
    }
}

/// A day of twelve lines of about 100 characters, stored the way a chat source stores them.
func splitDay(in store: Store) throws -> EvidenceSet {
    _ = try store.record(
        reading(dayLines(), grant: try permission(store)), of: .whatsAppChat, owner: try PersonID("owner"))
    let stored = try store.queries.currentLines(in: [chat], from: .distantPast, to: .distantFuture)
    return EvidenceSet(
        lines: stored.map {
            Evidence(
                id: $0.number, start: $0.time ?? start, line: $0.text, quotable: [$0.text], lineID: $0.lineID)
        })
}

func reading(_ lines: [ObservedLine], grant: CaptureGrant) -> SourceReading {
    SourceReading(
        grant: grant, label: chat, container: chat, audience: AudienceDigest(owner: "me", members: [member]),
        lines: lines, cursorAfter: nil, readerVersion: "check 1")
}

func dayLines() throws -> [ObservedLine] {
    try (1...12).map { number in
        ObservedLine(
            line: Line(
                entity: try EntityKey.whatsAppGroup(chat: chat, author: .member(member), stanzaID: "m\(number)"),
                text: "Asha: line-\(String(format: "%02d", number)) " + String(repeating: "x", count: 80),
                readerVersion: "check 1"),
            eventTime: UTCInstant(milliseconds: 1_795_000_000_000 + Int64(number) * 60_000), actor: member,
            messageRef: "m\(number)")
    }
}

/// Turns the chat on in the store's own policy, as the person does in the app, and returns its grant. The store checks
/// consent again inside each write against the saved policy, so a grant made only in memory is refused.
func permission(_ store: Store) throws -> CaptureGrant {
    let policy = CapturePolicy(switches: [.whatsapp: true], allowList: [.whatsapp: [chat]])
    try store.savePolicy(policy)
    guard let grant = policy.authorize(CaptureRequest(kind: .whatsapp, label: chat), at: store.clock()).grant else {
        throw CheckFailure(description: "no grant")
    }
    return grant
}

/// One tick of the app: send the lines no run read, part by part, and save each part before the next.
func tick(_ model: PartsModel, store: Store, day: EvidenceSet) async throws {
    let spec = HelperSpec.team
    let unread = try store.queries.unread(day, by: spec.task)
    guard !unread.newLines.isEmpty else { return }
    let reader = HelperReader(spec: spec, model: RecordedModel(model, store: store))
    _ = try await reader.readDay(
        day: WorkDay(containing: start), scope: chat, evidence: unread, budget: 450
    ) { part in
        try store.saveReading(
            part, of: spec, day: WorkDay(containing: start), scope: chat, grant: try permission(store))
    }
}

/// The numbers of the lines a model call shows as new, not as context.
func newNumbers(in input: String) -> [Int] {
    guard let marker = input.range(of: "New since the last reading") else {
        return input.split(separator: "\n").compactMap { numberOfLine($0) }
    }
    return input[marker.upperBound...].split(separator: "\n").compactMap { numberOfLine($0) }
}

func numberOfLine(_ line: Substring) -> Int? {
    guard let range = line.range(of: "line-") else { return nil }
    return Int(line[range.upperBound...].prefix(2))
}

heading("Split day (D4 G2)")
do {
    let store = try Store(directory: scratch.appending(path: "parts-ok"), clock: { start })
    let day = try splitDay(in: store)
    let model = PartsModel()
    try await tick(model, store: store, day: day)
    let first = model.inputs.withLock { $0 }.map(newNumbers)
    expect("a day of 12 lines is cut into 3 parts: \(first.map(\.count))", first.map(\.count) == [4, 4, 4])
    expect(
        "each line is sent as new once: \(first.flatMap { $0 }.sorted())",
        first.flatMap { $0 }.sorted() == Array(1...12))
    let yields = try store.queries.runs().map(\.kept)
    expect("each of the 3 runs has its own yield: \(yields)", yields == [0, 0, 0])
    try await tick(model, store: store, day: day)
    expect(
        "a second read sends no line again: \(model.inputs.withLock { $0.count }) calls in all",
        model.inputs.withLock { $0.count } == 3)

    let broken = try Store(directory: scratch.appending(path: "parts-fail"), clock: { start })
    let brokenDay = try splitDay(in: broken)
    let flaky = PartsModel(failing: [2])
    do { try await tick(flaky, store: broken, day: brokenDay) } catch {}
    let afterFailure = try broken.queries.runs().reversed().map {
        "\($0.outcome.rawValue)/\($0.kept.map(String.init) ?? "-")"
    }
    expect(
        "part 2 fails: its run is failed with no yield, part 1 is done with one: \(afterFailure)",
        afterFailure == ["done/0", "failed/-"])
    try await tick(flaky, store: broken, day: brokenDay)
    let again = flaky.inputs.withLock { $0 }.dropFirst(2).map(newNumbers)
    expect(
        "the next read sends the lines of part 2 and part 3, none of part 1: \(again)",
        again.flatMap { $0 }.sorted() == Array(5...12))
} catch {
    expect("Split day (D4 G2): ran without an error: \(error)", false)
}

// MARK: Failed attempts

struct Verdict: Decodable, Sendable { let label: String }

final class ScriptedLauncher: ProcessLauncher, Sendable {
    private let step: Result<ProcessOutput, any Error>

    init(_ step: Result<ProcessOutput, any Error>) { self.step = step }

    func launch(_ plan: ProcessPlan, timeout: Duration) async throws -> ProcessOutput { try step.get() }
}

func failedRun(_ name: String, _ step: Result<ProcessOutput, any Error>) async throws -> Run {
    let store = try Store(directory: scratch.appending(path: name), clock: { start })
    try store.confirmModelTerms()
    let runner = AgentRunner(
        kind: .claude, model: "opus", effort: "low", timeout: .seconds(5), launcher: ScriptedLauncher(step),
        executable: URL(filePath: "/opt/fake/claude"), environment: ["PATH": "/nonexistent", "HOME": scratch.path],
        workDirectory: scratch.appending(path: "work"))
    var policy = FailurePolicy()
    policy.settings.timeOutRetries = 0
    do {
        _ = try await RecordedModel(runner, store: store, policy: policy).generate(
            Verdict.self, schema: .object([.init("label", .string)]), task: "demo", instructions: "Say yes.",
            input: "made-up input", holding: [])
    } catch {}
    guard let run = try store.queries.runs().first else { throw CheckFailure(description: "no run in \(name)") }
    return run
}

let usageLine =
    #""total_cost_usd":0.5,"modelUsage":{"claude-opus":{"inputTokens":1000,"outputTokens":20,"cacheReadInputTokens":300,"cacheCreationInputTokens":40,"costUSD":0.5}}"#
let counted = Usage(inputTokens: 1000, cacheReadTokens: 300, cacheWriteTokens: 40, outputTokens: 20, costUSD: 0.5)

heading("Failed attempts (D4 G1)")
do {
    let limit = try await failedRun(
        "cli-error",
        .success(
            ProcessOutput(
                stdout: #"{"type":"result","subtype":"success","is_error":true,"result":"boom",\#(usageLine)}"#)))
    expect(
        "a CLI error result: tokens and cost are stored: \(String(describing: limit.usage))",
        limit.outcome == .failed && limit.usage == counted)

    let invalid = try await failedRun(
        "schema",
        .success(
            ProcessOutput(stdout: #"{"type":"result","is_error":false,"structured_output":{"label":5},\#(usageLine)}"#))
    )
    expect(
        "a reply that fails the schema: tokens and cost are stored",
        invalid.outcome == .failed && invalid.usage == counted)

    let killed = try await failedRun("killed", .failure(AgentCLIError.timedOut))
    expect(
        "a killed run (no result line): usage is NULL, not 0: \(String(describing: killed.usage))",
        killed.outcome == .failed && killed.usage == nil)

    let crashed = try await failedRun("crashed", .success(ProcessOutput(stdout: "", stderr: "segfault", status: 1)))
    expect("a crash with no result line: usage is NULL, not 0", crashed.outcome == .failed && crashed.usage == nil)

    let answered = try await failedRun(
        "answered",
        .success(
            ProcessOutput(
                stdout: #"{"type":"result","is_error":false,"structured_output":{"label":"yes"},\#(usageLine)}"#)))
    expect(
        "a good answer still stores its usage by the same parse: \(String(describing: answered.usage))",
        answered.outcome == .done && answered.usage == counted)
} catch {
    expect("Failed attempts (D4 G1): ran without an error: \(error)", false)
}

// MARK: Seeded pick

heading("Seeded audit pick (D6)")
do {
    let design = AuditPolicy.design(of: "team.ledger")
    let twice = (1...200).allSatisfy {
        AuditPolicy.pick(design: design, item: Int64($0)) == AuditPolicy.pick(design: design, item: Int64($0))
    }
    expect("the same (design, item) gives the same pick twice", twice)
    let picked = (1...10_000).filter { AuditPolicy.pick(design: design, item: Int64($0)) }.count
    let rate = Double(picked) / 10_000
    expect("over 10,000 ids the pick rate is 0.15 ± 0.01: \(rate)", abs(rate - RunSettings.standard.pickChance) <= 0.01)
    let other = AuditPolicy.design(of: "day.timeline")
    expect(
        "another design picks other items",
        (1...200).contains {
            AuditPolicy.pick(design: design, item: Int64($0)) != AuditPolicy.pick(design: other, item: Int64($0))
        })
}

// MARK: Home of a fact

struct Anything: Decodable, Sendable {}

heading("Home of a fact (G4b)")
do {
    let store = try Store(directory: scratch.appending(path: "home"), clock: { start })
    let folder = try store.createWorkObject(type: ObjectTypes.folder, parent: nil, name: "Follow-ups")
    let elsewhere = try store.createWorkObject(type: ObjectTypes.folder, parent: nil, name: "Elsewhere")
    let machine = try store.createMachine(from: .followUps, name: "Follow-ups", in: folder.id)
    let (_, run) = try await RecordedModel(PartsModel(), store: store).generate(
        Anything.self, schema: .object([.init("items", .array(.string))]), task: machine.spec.task, instructions: "v1",
        input: "x", holding: [.whatsapp])
    let day = WorkDay(containing: start)
    let item = Item(
        task: machine.spec.task, day: day, scope: chat, source: .whatsapp, citeFirst: 1, citeLast: 1, start: start,
        end: start, fields: ["who": "Asha", "owes": "you", "kind": "ask", "text": "Send the deck"], quote: "q", run: run
    )
    try store.saveReading(
        HelperReader.Result(items: [item], dropped: 0, run: run), of: machine.spec, day: day, scope: chat,
        grant: try permission(store))
    let id = try store.queries.items(of: machine.spec.task, day: day, scope: chat).compactMap(\.id).first ?? 0
    try store.file(item: id, into: elsewhere.id, how: .modelProposed)
    expect(
        "a newer model proposal leaves the machine folder as home",
        try store.queries.home(of: id)?.id == folder.id)
    expect("the proposal is the pending proposedHome", try store.queries.proposedHome(of: id)?.id == elsewhere.id)
    try store.confirmHome(of: id, surface: .today)
    expect("after confirmHome the home is the proposed object", try store.queries.home(of: id)?.id == elsewhere.id)
    expect(
        "after confirmHome the home was filed as personConfirmed",
        try store.queries.filing(of: id)?.how == .personConfirmed)
    expect("after confirmHome no proposal is pending", try store.queries.proposedHome(of: id) == nil)
} catch {
    expect("Home of a fact (G4b): ran without an error: \(error)", false)
}

heading("Consent inside the write (contract 86 §1)")
do {
    let store = try Store(directory: scratch.appending(path: "consent"), clock: { start })
    let grant = try permission(store)
    try store.savePolicy(CapturePolicy(switches: [.whatsapp: false], allowList: [.whatsapp: [chat]]))
    var refused = false
    do {
        _ = try store.record(reading(dayLines(), grant: grant), of: .whatsAppChat, owner: try PersonID("owner"))
    } catch EvidenceError.consentWithdrawn {
        refused = true
    }
    expect("a write after the person turned the chat off is refused", refused)
    expect(
        "no line of the refused write is stored",
        try store.queries.currentLines(in: [chat], from: .distantPast, to: .distantFuture).isEmpty)
} catch {
    expect("Consent inside the write: ran without an error: \(error)", false)
}

if let failed {
    print("\nFAILED: \(failed)")
    exit(1)
}
print("\nALL OK")
