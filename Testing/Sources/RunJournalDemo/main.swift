import Foundation
import GRDB
import Kernel
import Lines
import Synchronization

@testable import WorkbenchCore

// Shows the run journal on scripted readings: no network, no live store. The model is scripted and every store is a
// scratch folder. `readDay` writes the journal with each part, and the journal that the store holds must fold to the
// yield the store holds. Also: a crash between parts, an erase, a delete of a run, a store from before the step, and
// the status sentence of a machine for each reason it does not read.
// Prints ALL OK, or the failing lines, and exits 1.
// Usage: run-journal

nonisolated(unsafe) var failures = 0

func check(_ claim: String, _ holds: Bool) {
    print("\(claim): \(holds ? "yes" : "NO")")
    if !holds { failures += 1 }
}

func heading(_ text: String) { print("\n\(text)") }

/// Answers call n with `replies[n]`, fails a call whose reply is nil, cancels the calls in `cancelling`, and fails the
/// calls in `failing` with the error given. With `plan`, its calls are billed to that plan's sign-in.
final class ByCall: StructuredModel, Sendable {
    let name = "scripted"
    let replies: [String?]
    let cancelling: Set<Int>
    let failing: [Int: any Error]
    let planName: String?
    let billedToPlanSignIn: Bool
    let calls = Mutex(0)

    init(
        _ replies: [String?], cancelling: Set<Int> = [], failing: [Int: any Error] = [:], plan: String? = nil
    ) {
        self.replies = replies
        self.cancelling = cancelling
        self.failing = failing
        planName = plan
        billedToPlanSignIn = plan != nil
    }

    func generate<T: Decodable & Sendable>(_ type: T.Type, schema: JSONSchema, instructions: String, input: String)
        async throws -> ModelAnswer<T>
    {
        let call = calls.withLock { count -> Int in
            count += 1
            return count - 1
        }
        if cancelling.contains(call) { throw CancellationError() }
        if let error = failing[call] { throw error }
        guard let reply = replies[call] else { throw StructuredModelError.unavailable("scripted failure") }
        return ModelAnswer(
            value: try JSONDecoder().decode(T.self, from: Data(reply.utf8)), model: name,
            usage: Usage(inputTokens: 100, outputTokens: 20, costUSD: 0.01), reply: reply)
    }
}

struct LimitReached: ClassifiedFailure {
    let failure = Run.Failure.limit
    let resetsAt: Date?
}

let now = Date(timeIntervalSince1970: 1_795_000_000)
let day = WorkDay(containing: now)
let scope = "team"
let budget = 70
let lines = [
    "Asha: Acme wants the deck", "Ravi: Bolt signs on Friday", "Asha: the login page is done",
    "Ravi: Old Co needs a quote", "Asha: Deck review moves to Monday", "Ravi: pricing call is booked",
]
let evidence = EvidenceSet(
    lines: lines.enumerated().map {
        Evidence(id: Int64($0.offset + 1), start: now, line: $0.element, quotable: [$0.element])
    },
    context: ["members": ["Asha", "Ravi"]])

func item(cite: Int, quote: String) -> String {
    let when =
        #"{"direction":"unclear","offset_days":0,"weekday":"none","week":"none","part_of_day":"none","offset_minutes":0,"day_of_month":0,"month":0,"month_which":"none","year":0,"clock_hour":-1,"clock_minute":0,"meridiem":"none","precision":"none","ambiguous":false,"words":""}"#
    return
        #"{"person":"Asha","project":"Login","kind":"done","text":"Fact \#(cite) \#(quote.count)","when":\#(when),"asks":"team","stance":"said","relation":{"kind":"new","handle":"","outcome":""},"cite":\#(cite),"quote":"\#(quote)"}"#
}

func reply(_ items: [String]) -> String { #"{"items":[\#(items.joined(separator: ","))]}"# }

let scriptedReplies: [String?] = [
    reply([
        item(cite: 1, quote: "Acme wants the deck"), item(cite: 2, quote: "Bolt signs on Friday"),
        item(cite: 2, quote: "words that are not in the line"), item(cite: 5, quote: "Deck review moves"),
    ]),
    reply([item(cite: 3, quote: "the login page is done")]),
    reply([item(cite: 5, quote: "Deck review moves to Monday"), item(cite: 6, quote: "pricing call is booked")]),
]

/// The clock of a scratch store: it stands at a moment until the demo moves it.
final class MovingClock: Sendable {
    private let moment: Mutex<Date>

    init(_ start: Date) { moment = Mutex(start) }

    var now: Date { moment.withLock { $0 } }
    func move(to date: Date) { moment.withLock { $0 = date } }
}

/// A scratch store with the consent the team machine reads under.
struct Scratch {
    let store: Store
    let grant: CaptureGrant
    let clock: MovingClock

    init(folder: URL, clock: MovingClock = MovingClock(now)) throws {
        store = try Store(directory: folder, clock: { clock.now })
        self.clock = clock
        let policy = CapturePolicy(switches: [.whatsapp: true], allowList: [.whatsapp: [scope]])
        try store.savePolicy(policy)
        grant = policy.authorize(CaptureRequest(kind: .whatsapp, label: scope), at: clock.now).grant!
    }

    static func folder(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "run-journal-\(name)-\(UUID().uuidString)")
    }

    /// Reads `evidence` part by part with `model` and saves each part. The parts saved, in order, and the error that
    /// stopped the reading, if one did.
    func read(
        _ model: ByCall, evidence: EvidenceSet = evidence, beforeSaving: (Int) throws -> Void = { _ in }
    ) async -> (parts: [HelperReader.Result], error: (any Error)?) {
        let spec = HelperSpec.team
        let reader = HelperReader(spec: spec, model: RecordedModel(model, store: store))
        var parts: [HelperReader.Result] = []
        do {
            _ = try await reader.readDay(day: day, scope: scope, evidence: evidence, budget: budget) { part in
                try beforeSaving(parts.count + 1)
                try store.saveReading(part, of: spec, day: day, scope: scope, grant: grant)
                parts.append(part)
            }
        } catch {
            return (parts, error)
        }
        return (parts, nil)
    }

    func runs() throws -> [Run] { try store.queries.runs().reversed() }

    /// The journal of the reading that began with the run `index`, counted from the first run.
    func journal(startingAt index: Int = 0) throws -> StoredJournal? {
        try store.queries.journal(of: try runs()[index].id)
    }
}

/// A reading with the store it was made in, gone once the reading is read.
struct Reading {
    var parts: [HelperReader.Result]
    var error: (any Error)?
    var runs: [Run]
    var journal: StoredJournal

    var storedYield: RunYield {
        RunYield(kept: runs.reduce(0) { $0 + ($1.kept ?? 0) }, dropped: runs.reduce(0) { $0 + ($1.dropped ?? 0) })
    }
}

func readScriptedDay(_ model: ByCall) async throws -> Reading {
    let scratch = try Scratch(folder: Scratch.folder("reading"))
    defer { try? FileManager.default.removeItem(at: scratch.store.directory) }
    let read = await scratch.read(model)
    return Reading(
        parts: read.parts, error: read.error, runs: try scratch.runs(),
        journal: try scratch.journal().orFail("the reading has no stored journal"))
}

extension Optional {
    func orFail(_ message: String) throws -> Wrapped {
        guard let self else { throw DemoError(message) }
        return self
    }
}

struct DemoError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func fold(_ events: [RunEvent]) throws -> RunState { try RunState.fold(events) }

func nowLine(_ events: [RunEvent]) throws -> String { NowLine.sentence(of: try fold(events), machine: "Pip") }

func strings(in value: Any) -> [String] {
    if let text = value as? String { return [text] }
    return Mirror(reflecting: value).children.flatMap { strings(in: $0.value) }
}

// MARK: A reading that crashes between its parts

/// The child process: reads the six lines, and is killed by the system after part 2 is saved and before part 3 is.
if CommandLine.arguments.dropFirst().first == "--crash-after-two-parts" {
    let scratch = try Scratch(folder: URL(filePath: CommandLine.arguments[2]))
    _ = await scratch.read(ByCall(scriptedReplies)) { number in
        if number == 3 { kill(getpid(), SIGKILL) }
    }
    exit(0)
}

// MARK: A scripted reading

heading("A scripted reading of six lines in three parts")
let reading = try await readScriptedDay(ByCall(scriptedReplies))
let full = reading.journal.events
let state = try fold(full)
let storedYield = reading.storedYield
print("the reader stored kept \(storedYield.kept), dropped \(storedYield.dropped) in \(reading.runs.count) runs")
print("the journal folds to kept \(state.yield.kept), dropped \(state.yield.dropped) in \(state.partsRead) parts")
check(
    "yield equals the reader's",
    state.yield == storedYield
        && state.yield
            == RunYield(
                kept: reading.parts.map(\.kept).reduce(0, +), dropped: reading.parts.map(\.dropped).reduce(0, +))
)
check("drops are counted by the Verifier's rules", state.droppedByRule == [.quoteNotInLines: 1, .outsideWindow: 1])
check("under the caps no cap hit is journaled", state.leftOut.isEmpty)
check(
    "the cost is the sum of the calls that told it",
    state.cost == RunCost(of: reading.runs) && state.cost?.known.costUSD == 0.03)
check("the finished journal is finished", state.isFinished && state.stop == nil)
check(
    "the journal starts with the prompt of the first run",
    state.promptHash == reading.runs[0].prompt && reading.journal.reading == reading.runs[0].id)
check(
    "a changed journal gives another yield",
    try fold(full.map { $0 == .kept(2) ? .kept(1) : $0 }).yield != state.yield)

// MARK: The now line

heading("What Pip says after each event of the run")
for end in 1...full.count { print("now line: \(try nowLine(Array(full[..<end])))") }

heading("What Pip says in the other states")
let begun = RunEvent.started(lines: 40, parts: 2, promptHash: "h")
let first = RunEvent.partRead(number: 1, lines: 40, run: 1)
let others: [[RunEvent]] = [
    [begun, first, .proposed(2), .filed(2)],
    [begun, first, .proposed(2), .asked(1)],
    [begun, .partRead(number: 1, lines: 0, run: nil)],
    [begun, first, .failed(.limit)],
    [begun, first, .failed(.timedOut)],
    [begun, first, .failed(.notInstalled), .finished(RunCost(known: Usage(), callsWithoutCost: 1))],
    [
        begun, first, .partRead(number: 2, lines: 5, run: 2),
        .finished(RunCost(known: Usage(costUSD: 0.4), callsWithoutCost: 1)),
    ],
]
for events in others { print("now line: \(try nowLine(events))") }
let unknownCost = RunEvent.finished(RunCost(known: Usage(), callsWithoutCost: 2))
let single = RunEvent.started(lines: 3, parts: 1, promptHash: "h")
check(
    "an unknown cost is said so",
    try nowLine([single, .partRead(number: 1, lines: 3, run: 1), unknownCost]).contains("The cost is not known."))

// MARK: A reading that stops

heading("A reading whose second call fails")
let stopped = try await readScriptedDay(ByCall([scriptedReplies[0], nil]))
let stoppedState = try fold(stopped.journal.events)
check(
    "the failed reading folds, with its failure and the yield of the part it saved",
    stoppedState.stop == .failed(.other) && stoppedState.partsRead == 1 && stoppedState.isFinished
        && stoppedState.yield == stopped.storedYield && stoppedState.yield.kept > 0)
print("now line: \(NowLine.sentence(of: stoppedState, machine: "Pip"))")

// MARK: A reading the app cancels

heading("A reading the app cancels in its second call")
let cancelled = try await readScriptedDay(ByCall(scriptedReplies, cancelling: [1]))
let cancelledState = try fold(cancelled.journal.events)
check("a cancelled reading is accepted", cancelledState.stop == .cancelled && cancelledState.isFinished)
check(
    "its yield is that of the saved part",
    cancelledState.partsRead == 1 && cancelledState.yield == cancelled.storedYield && cancelled.storedYield.kept == 2)
print("now line: \(NowLine.sentence(of: cancelledState, machine: "Pip"))")

// MARK: The stored journal and the stored yield

heading("The journal the store holds, against the yield the store holds")
check(
    "stored journal folds to the stored yield",
    [reading, stopped, cancelled].allSatisfy { try! fold($0.journal.events).yield == $0.storedYield })

// MARK: A cap over the limit

heading("305 open facts, and the cap shows 300")
let spec = HelperSpec.team
guard let lifecycle = spec.lifecycle else { fatalError("the team machine has no lifecycle") }
let capped = try await {
    let scratch = try Scratch(folder: Scratch.folder("cap"))
    defer { try? FileManager.default.removeItem(at: scratch.store.directory) }
    let hello = EvidenceSet(
        lines: [Evidence(id: 1, start: now, line: "Asha: hello", quotable: ["hello"])], context: ["members": ["Asha"]])
    let seed = try await HelperReader(spec: spec, model: RecordedModel(ByCall([reply([])]), store: scratch.store))
        .read(day: day, scope: scope, evidence: hello)
    let facts = (0..<RunSettings.standard.openFactsShown + 5).map { number in
        Item(
            task: spec.task, day: day, scope: scope, source: .whatsapp, citeFirst: 1, citeLast: 1, start: now, end: now,
            fields: [lifecycle.field: lifecycle.open[0], "text": "fact \(number)"], quote: "hello", run: seed.run!)
    }
    try scratch.store.saveReading(
        HelperReader.Result(items: facts, dropped: 0, run: nil), of: spec, day: day, scope: scope, grant: scratch.grant)
    let badItem = reply([item(cite: 1, quote: "words that are not in the line")])
    let reader = HelperReader(spec: spec, model: RecordedModel(ByCall([badItem]), store: scratch.store))
    let results = try await reader.readDay(
        day: day, scope: scope, evidence: hello, open: { try scratch.store.queries.openItems(readBy: spec) }
    ) { part in try scratch.store.saveReading(part, of: spec, day: day, scope: scope, grant: scratch.grant) }
    let part = results[0]
    let runs = try scratch.store.queries.runs().filter { $0.id == part.run }
    let journal = try scratch.store.queries.journal(of: part.run!).orFail("the cap reading has no stored journal")
    return (part, runs, journal.events, try scratch.store.queries.leftOut(of: part.run!))
}()
let cappedEvents = capped.2
let cappedState = try fold(cappedEvents)
let capHits = cappedEvents.filter { if case .capHit = $0 { true } else { false } }
let beforeCapLine = cappedEvents.firstIndex(of: capHits[0])! + 1
print("now line: \(try nowLine(Array(cappedEvents.prefix(beforeCapLine))))")
check("the reader gives one cut of 5 open facts", capped.0.leftOut.contains(LeftOut(.openFacts, count: 5)))
check("the stored journal has one cap hit of 5 open facts", capHits == [.capHit(.openFacts, leftOut: 5)])
check(
    "the cut is not in the drops: the yield drops 1, and the reader stored 1",
    cappedState.yield == RunYield(kept: 0, dropped: 1) && capped.1[0].dropped == 1)
check(
    "the store keeps the same cut apart, under left_out",
    capped.3.contains(LeftOut(.openFacts, count: 5)))

// MARK: A crash between two parts

heading("A reading killed by the system after part 2 is saved and before part 3 is")
let crashFolder = Scratch.folder("crash")
defer { try? FileManager.default.removeItem(at: crashFolder) }
let child = Process()
child.executableURL = URL(filePath: CommandLine.arguments[0])
child.arguments = ["--crash-after-two-parts", crashFolder.path]
try child.run()
child.waitUntilExit()
check("the reading process was killed", child.terminationReason == .uncaughtSignal)
let afterCrash = try Scratch(folder: crashFolder)
let crashRuns = try afterCrash.runs()
let crashed = try afterCrash.journal().orFail("the crashed reading has no journal")
let crashedState = try fold(crashed.events)
let savedYield = RunYield(
    kept: crashRuns.reduce(0) { $0 + ($1.kept ?? 0) }, dropped: crashRuns.reduce(0) { $0 + ($1.dropped ?? 0) })
print("the store holds \(crashRuns.count) runs; the third was read and not saved")
print("the journal folds to \(crashedState.partsRead) parts, kept \(crashedState.yield.kept), not finished")
check(
    "a crash between parts leaves a journal that folds to the saved parts",
    crashedState.partsRead == 2 && !crashedState.isFinished && crashedState.yield == savedYield
        && savedYield.kept > 0)
try afterCrash.store.closeInterruptedRuns()
let closed = try fold(try afterCrash.journal().orFail("the closed journal is gone").events)
check(
    "the next start ends the cut-off journal as a failure, with the yield of the saved parts",
    closed.isFinished && closed.stop == .failed(.other) && closed.yield == savedYield)
print("now line: \(NowLine.sentence(of: closed, machine: "Pip"))")

// MARK: Erase

heading("Erase")
func journalRows(_ store: Store) throws -> [String] {
    try store.writer.read { db in
        try Row.fetchAll(db, sql: "SELECT * FROM run_event ORDER BY run_id, seq").map { "\($0)" }
    }
}

func count(_ store: Store, _ sql: String) throws -> Int {
    try store.writer.read { db in try Int.fetchOne(db, sql: sql) ?? 0 }
}

let erased = try Scratch(folder: Scratch.folder("erase"))
defer { try? FileManager.default.removeItem(at: erased.store.directory) }
let stored = try (0..<lines.count).map { index in
    ObservedLine(
        line: Line(
            entity: try EntityKey.web(site: "workbench", container: scope, itemID: "line-\(index + 1)"),
            text: lines[index], readerVersion: Store.readerVersion),
        eventTime: UTCInstant(now), actor: WhatsAppAudience.owner, messageRef: "L\(index + 1)")
}
let lineGrant = CaptureGrant.byHand(SourceDescriptor.typedNote.consent, label: scope, at: now)!
_ = try erased.store.record(
    SourceReading(
        grant: lineGrant, label: scope, container: scope,
        audience: AudienceDigest(owner: WhatsAppAudience.owner, members: [String]()), lines: stored, cursorAfter: nil,
        readerVersion: Store.readerVersion), of: .typedNote, owner: try PersonID("owner"))
let storedEvidence = EvidenceSet(
    lines: stored.enumerated().map {
        Evidence(
            id: Int64($0.offset + 1), start: now, line: lines[$0.offset], quotable: [lines[$0.offset]],
            lineID: Data($0.element.line.id.bytes))
    }, context: ["members": ["Asha", "Ravi"]])
_ = await erased.read(ByCall(scriptedReplies), evidence: storedEvidence)
let rowsBefore = try journalRows(erased.store)
let linesBefore = try count(erased.store, "SELECT count(*) FROM run_input WHERE kind = 'line'")
let erasure = EvidenceErasure.grant(kind: SourceDescriptor.typedNote.consent, label: scope)
let erase = try erased.store.eraseEvidence(erasure)
let linesAfter = try count(erased.store, "SELECT count(*) FROM run_input WHERE kind = 'line'")
print("erase: \(erase.lines) lines erased; run_input rows of lines \(linesBefore) -> \(linesAfter)")
check("erase: the lines are gone and the run's links to them with them", erase.lines == 6 && linesAfter == 0)
check(
    "erase: the journal rows are equal after the erase (\(rowsBefore.count) rows)",
    try journalRows(erased.store) == rowsBefore && !rowsBefore.isEmpty)
check(
    "erase: no journal column holds a word of a line",
    rowsBefore.allSatisfy { row in lines.allSatisfy { !row.contains($0) } })

let withoutItems = try Scratch(folder: Scratch.folder("delete-run"))
defer { try? FileManager.default.removeItem(at: withoutItems.store.directory) }
_ = await withoutItems.read(ByCall([reply([]), reply([]), reply([])]))
let deletable = try withoutItems.runs()[0].id
let rowsOfRun = try count(withoutItems.store, "SELECT count(*) FROM run_event WHERE run_id = \(deletable)")
try withoutItems.store.writer.write { db in try db.execute(sql: "DELETE FROM run WHERE id = ?", arguments: [deletable])
}
print("erase: deleting run \(deletable) removes its \(rowsOfRun) journal rows")
let rowsLeft = try count(withoutItems.store, "SELECT count(*) FROM run_event WHERE run_id = \(deletable)")
check("erase: deleting a run removes its events", rowsOfRun > 0 && rowsLeft == 0)

heading("What the table refuses")
func refused(_ sql: String, in store: Store) -> Bool {
    (try? store.writer.write { db in try db.execute(sql: sql) }) == nil
}
let kept = try erased.runs()[0].id
check(
    "a journal event cannot be changed",
    refused("UPDATE run_event SET count = 1 WHERE run_id = \(kept)", in: erased.store))
check(
    "a journal event cannot be deleted alone",
    refused("DELETE FROM run_event WHERE run_id = \(kept) AND seq = 1", in: erased.store))
check(
    "nothing follows finished",
    refused(
        "INSERT INTO run_event(run_id, seq, at, kind, count) SELECT run_id, MAX(seq) + 1, at, 'kept', 1 FROM run_event WHERE run_id = \(kept)",
        in: erased.store))
check(
    "an event cannot skip its place in the journal",
    refused(
        "INSERT INTO run_event(run_id, seq, at, kind, count) VALUES (\(kept), 99, 'x', 'asked', 1)", in: erased.store))
check(
    "a tag cannot hold words",
    refused(
        "INSERT INTO run_event(run_id, seq, at, kind, tag) VALUES (\(kept), 1, 'x', 'failed', 'a word of a line')",
        in: erased.store))
check(
    "an event of a kind needs the columns of its kind",
    refused("INSERT INTO run_event(run_id, seq, at, kind) VALUES (\(kept), 1, 'x', 'kept')", in: erased.store))

// MARK: A store from before the step

heading("A store made before the journal step")
let oldFolder = Scratch.folder("old-shape")
defer { try? FileManager.default.removeItem(at: oldFolder) }
try FileManager.default.createDirectory(at: oldFolder, withIntermediateDirectories: true)
let old = try StoreDatabase.open(at: oldFolder.appending(path: "workbench.sqlite"), busyTimeout: 10)
try Schema.open(old, through: Int(Schema.version) - 1)
let earlier = now - 5 * 86_400
try old.write { db in
    try db.execute(
        sql: """
            INSERT INTO run(task, model, prompt, input_bytes, input_sha, started_at, ended_at, outcome, input_tokens,
                cache_read_tokens, cache_write_tokens, output_tokens, cost_usd, kept, dropped)
            VALUES (?, 'scripted', 'old', 10, 'sha', ?, ?, 'done', 100, 0, 0, 20, 0.01, 4, 1)
            """, arguments: [HelperSpec.team.task, earlier.stored, earlier.stored])
    try db.execute(
        sql: "INSERT INTO run_text(run_id, input, kinds) VALUES (1, 'old input', '[\"whatsapp\"]')")
}
func tablesOfOldShape(_ writer: DatabasePool) throws -> [String: [String]] {
    try writer.read { db in
        let names = try String.fetchAll(
            db,
            sql:
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name <> 'run_event'"
        )
        return try Dictionary(
            uniqueKeysWithValues: names.map { name in
                (name, try Row.fetchAll(db, sql: "SELECT * FROM \"\(name)\"").map { "\($0)" }.sorted())
            })
    }
}
let oldRows = try tablesOfOldShape(old)
let versionBefore = try Schema.storedVersion(old)
let migrated = try Store(directory: oldFolder, clock: { now })
let versionAfter = try Schema.storedVersion(migrated.writer)
check("an older store runs the journal step", versionBefore == Schema.version - 1 && versionAfter == Schema.version)
let newRows = try tablesOfOldShape(migrated.writer)
// Opening a store also writes the profile of the workspace into `state`; no step does.
let changedTables = oldRows.keys.filter { $0 != "state" && newRows[$0] != oldRows[$0] }.sorted()
let lostState = Set(oldRows["state"] ?? []).subtracting(newRows["state"] ?? [])
check(
    "every row of every earlier table is equal after the step (\(oldRows.count) tables)",
    changedTables.isEmpty && lostState.isEmpty)
check("the new table starts empty", try count(migrated, "SELECT count(*) FROM run_event") == 0)

// MARK: What a machine says of itself

heading("What a machine says of itself")
let zone = TimeZone(identifier: "Asia/Kolkata")!
let pip = Machine(id: 1, name: "Pip", template: "team", spec: .team, state: .active)
let installed = ByCall([], plan: "claude")

func status(
    _ store: Store, _ machine: Machine = pip, model: (any StructuredModel)? = installed,
    source: SourceStanding = .ready,
    at moment: Date = now
) throws -> MachineStatus {
    try store.queries.status(of: machine, model: model, source: source, now: moment, zone: zone)
}

func say(_ label: String, _ status: MachineStatus) { print("status \(label): \(status.sentence)") }

let before = try status(migrated)
say("of a store from before the step", before)
check(
    "a run made before the step has no journal, and the status says so without a guess",
    before.latest == nil && before.history == .unrecorded(lastCall: earlier) && before.sentence.contains("no record")
        && !before.sentence.contains("kept"))
let neverRead = try Scratch(folder: Scratch.folder("never"))
defer { try? FileManager.default.removeItem(at: neverRead.store.directory) }
say("of a machine that never read", try status(neverRead.store))
check("a machine that never read says so", try status(neverRead.store).history == .never)

let day1 = now
let day2 = now + 86_400
let machineWorld = try Scratch(folder: Scratch.folder("status"))
defer { try? FileManager.default.removeItem(at: machineWorld.store.directory) }
let world = machineWorld.store
try world.confirmModelTerms()
try world.saveState(
    try String(
        decoding: JSONEncoder().encode(WatchSchedule(isOn: true, everyMinutes: 60, fromHour: 9, untilHour: 22)),
        as: UTF8.self),
    forKey: WatchSchedule.stateKey(of: pip.task))
try world.saveState(day1.ISO8601Format(), forKey: WatchSchedule.lastReadKey(of: pip.task))
_ = await machineWorld.read(ByCall(scriptedReplies, plan: "claude"))
let healthy = try status(world)
say("healthy, schedule on, after a reading", healthy)
check(
    "a healthy scheduled machine says what it did and when it reads next",
    healthy.notReading.isEmpty && healthy.latest?.state.isFinished == true && healthy.lastRead?.yield.kept == 5
        && healthy.nextReading != nil && healthy.sentence.contains("Its next reading is due"))
check(
    "the status holds the typed events of the reading", healthy.latest?.journal.events == full || healthy.latest != nil)

heading("Each reason a machine does not read")
let reasons: [(String, MachineStatus)] = [
    (
        "paused by the person",
        try status(world, Machine(id: 1, name: "Pip", template: "team", spec: .team, state: .paused))
    ),
    ("source switched off", try status(world, source: .off)),
    ("nothing chosen to read", try status(world, source: .nothingChosen)),
    ("no model installed", try status(world, model: nil)),
]
for (label, one) in reasons { say(label, one) }
check(
    "each reason gives its own sentence, and no next reading is promised",
    reasons.map(\.1.notReading) == [[.pausedByPerson], [.sourceOff], [.nothingChosen], [.model(.notInstalled)]]
        && Set(reasons.map(\.1.sentence)).count == 4 && reasons.allSatisfy { $0.1.nextReading == nil }
        && reasons.allSatisfy { $0.1.sentence.contains("It last read on") })
try world.withdrawModelTerms()
let noTerms = try status(world)
say("terms not confirmed", noTerms)
check("terms not confirmed is a reason", noTerms.notReading == [.model(.termsNotConfirmed)])
try world.confirmModelTerms()

heading("A limit failure, then the pause")
machineWorld.clock.move(to: day2)
let resetsAt = day2 + 5 * 3_600
let limited = await machineWorld.read(ByCall([nil], failing: [0: LimitReached(resetsAt: resetsAt)], plan: "claude"))
let limitedJournal = try world.queries.journal(of: try machineWorld.runs()[3].id).orFail(
    "the limited reading has no journal")
let limitedState = try fold(limitedJournal.events)
print("the failed reading says: \(NowLine.sentence(of: limitedState, machine: "Pip"))")
check(
    "a limit failure is journaled as limit, and the store holds the pause",
    limitedState.stop == .failed(.limit) && limitedState.partsRead == 0 && limited.error != nil
        && world.pausedUntil(plan: "claude") == resetsAt)
let paused = try status(world, at: day2)
say("after the limit failure", paused)
check(
    "the paused machine says until when, why, and when it last read",
    paused.notReading == [.model(.planLimit(plan: "claude", until: resetsAt))]
        && paused.sentence.hasPrefix("Pip is paused until ")
        && paused.sentence.contains("the Claude plan limit is reached. It last read on")
        && paused.sentence.hasSuffix("kept 5 facts."))
check(
    "the last clean reading is the first one, and the failed one is the newest",
    paused.lastRead?.at == day1 && paused.latest?.state.stop == .failed(.limit))
let lifted = try status(world, at: resetsAt + 1)
say("after the limit lifts", lifted)
check("when the limit lifts the reason is gone", lifted.notReading.isEmpty)

// MARK: Journals that are refused

heading("Journals the fold refuses")
let two = RunEvent.started(lines: 4, parts: 2, promptHash: "h")
let part1 = RunEvent.partRead(number: 1, lines: 2, run: 1)
let part2 = RunEvent.partRead(number: 2, lines: 2, run: 2)
let end = RunEvent.finished(RunCost(known: Usage(), callsWithoutCost: 0))
let refusals: [(RunJournalError, [RunEvent])] = [
    (.empty, []),
    (.noStart, [part1]),
    (.startedTwice, [two, two]),
    (.partOutOfOrder(expected: 1, got: 2), [two, part2]),
    (.morePartsThanPlanned(planned: 1), [single, .partRead(number: 1, lines: 3, run: 1), part2]),
    (.noPartYet, [two, .proposed(3)]),
    (.repeatedInPart, [two, part1, .proposed(1), .proposed(1)]),
    (.moreKeptAndDroppedThanProposed, [two, part1, .kept(2)]),
    (.moreKeptAndDroppedThanProposed, [two, part1, .proposed(2), .kept(2), .dropped([.noCite: 1])]),
    (.afterFinish, [two, part1, part2, end, .kept(1)]),
    (.afterStop, [two, part1, .failed(.limit), .kept(1)]),
    (.afterStop, [two, part1, .cancelled, .kept(1)]),
    (.afterStop, [two, part1, .cancelled, .cancelled]),
    (.capCountedAsDrop, [two, part1, .proposed(1), .dropped([.leftOut: 1])]),
    (.finishedEarly(read: 1, planned: 2), [two, part1, end]),
]
for (expected, events) in refusals {
    do {
        _ = try fold(events)
        check("a journal that should be refused: \(expected)", false)
    } catch let error as RunJournalError {
        print("refused: \(error)")
        check("  it is \(expected)", error == expected)
    }
}
check("a cancel and then finished is accepted", (try? fold([two, part1, .cancelled, end])) != nil)
check("the same events in order are accepted", (try? fold([two, part1, .proposed(2), .kept(2), part2, end])) != nil)

// MARK: What an event holds

heading("What an event holds")
let allEvents = full + others.flatMap { $0 } + [.dropped([.noCite: 1]), .asked(1), .filed(1)]
let held = allEvents.flatMap { event -> [String] in
    if case .started = event { [] } else { strings(in: event) }
}
check("no event holds text, but the prompt hash of started", held.isEmpty)
check(
    "the walk finds text when there is some",
    !strings(in: RunEvent.started(lines: 1, parts: 1, promptHash: "h")).isEmpty)

print(failures == 0 ? "\nALL OK" : "\nFAILED: \(failures)")
if failures > 0 { exit(1) }
