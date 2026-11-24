import Foundation
import Synchronization
import WorkbenchCore

// Shows the run journal on a scripted reading: no network, no live store. The model is scripted and the store is a
// scratch folder. The journal comes from what `HelperReader` returns; its fold must give the yield the reader stored.
// Prints ALL OK, or the failing lines, and exits 1.
// Usage: run-journal

nonisolated(unsafe) var failures = 0

func check(_ claim: String, _ holds: Bool) {
    print("\(claim): \(holds ? "yes" : "NO")")
    if !holds { failures += 1 }
}

func heading(_ text: String) { print("\n\(text)") }

/// Answers call n with `replies[n]`, fails a call whose reply is nil, and cancels the calls in `cancelling`.
final class ByCall: StructuredModel, Sendable {
    let name = "scripted"
    let replies: [String?]
    let cancelling: Set<Int>
    let calls = Mutex(0)

    init(_ replies: [String?], cancelling: Set<Int> = []) {
        self.replies = replies
        self.cancelling = cancelling
    }

    func generate<T: Decodable & Sendable>(_ type: T.Type, schema: JSONSchema, instructions: String, input: String)
        async throws -> ModelAnswer<T>
    {
        let call = calls.withLock { count -> Int in
            count += 1
            return count - 1
        }
        if cancelling.contains(call) { throw CancellationError() }
        guard let reply = replies[call] else { throw StructuredModelError.unavailable("scripted failure") }
        return ModelAnswer(
            value: try JSONDecoder().decode(T.self, from: Data(reply.utf8)), model: name,
            usage: Usage(inputTokens: 100, outputTokens: 20, costUSD: 0.01), reply: reply)
    }
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

/// Reads the six lines part by part with `replies` and saves each part. Returns the parts the reader gave, in order,
/// the runs the store holds, how it stopped is in the runs.
func readScriptedDay(replies: [String?], cancelling: Set<Int> = []) async throws -> (
    parts: [HelperReader.Result], runs: [Run]
) {
    let store = try Store(
        directory: FileManager.default.temporaryDirectory.appending(path: "run-journal-\(UUID().uuidString)"),
        clock: { now })
    defer { try? FileManager.default.removeItem(at: store.directory) }
    let policy = CapturePolicy(switches: [.whatsapp: true], allowList: [.whatsapp: [scope]])
    try store.savePolicy(policy)
    let grant = policy.authorize(CaptureRequest(kind: .whatsapp, label: scope), at: now).grant!
    let spec = HelperSpec.team
    let reader = HelperReader(spec: spec, model: RecordedModel(ByCall(replies, cancelling: cancelling), store: store))
    var parts: [HelperReader.Result] = []
    do {
        _ = try await reader.readDay(day: day, scope: scope, evidence: evidence, budget: budget) { part in
            try store.saveReading(part, of: spec, day: day, scope: scope, grant: grant)
            parts.append(part)
        }
    } catch {}
    let runs = try store.queries.runs().reversed() as [Run]
    return (parts, runs)
}

/// The journal of a reading: its start, the events of each part it read, and its end.
func journal(of reading: (parts: [HelperReader.Result], runs: [Run])) -> [RunEvent] {
    let sizes = HelperReader.partSizes(of: evidence, budget: budget)
    let start = RunEvent.start(of: evidence, budget: budget, promptHash: reading.runs[0].prompt)
    let parts = reading.parts.enumerated().flatMap { index, part in
        RunEvent.events(of: part, number: index + 1, lines: sizes[index])
    }
    return [start] + parts + RunEvent.ending(runs: reading.runs)
}

func fold(_ events: [RunEvent]) throws -> RunState { try RunState.fold(events) }

func nowLine(_ events: [RunEvent]) throws -> String { NowLine.sentence(of: try fold(events), machine: "Pip") }

func strings(in value: Any) -> [String] {
    if let text = value as? String { return [text] }
    return Mirror(reflecting: value).children.flatMap { strings(in: $0.value) }
}

// MARK: A scripted run

heading("A scripted reading of six lines in three parts")
let reading = try await readScriptedDay(replies: scriptedReplies)
let full = journal(of: reading)
let state = try fold(full)
let storedKept = reading.runs.reduce(0) { $0 + ($1.kept ?? 0) }
let storedDropped = reading.runs.reduce(0) { $0 + ($1.dropped ?? 0) }
print("the reader stored kept \(storedKept), dropped \(storedDropped) in \(reading.runs.count) runs")
print("the journal folds to kept \(state.yield.kept), dropped \(state.yield.dropped) in \(state.partsRead) parts")
check(
    "yield equals the reader's",
    state.yield == RunYield(kept: storedKept, dropped: storedDropped)
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
let stopped = try await readScriptedDay(replies: [scriptedReplies[0], nil])
let stoppedState = try fold(journal(of: stopped))
let stoppedKept = stopped.runs.reduce(0) { $0 + ($1.kept ?? 0) }
check(
    "the failed reading folds, with its failure and the yield of the part it saved",
    stoppedState.stop == .failed(.other) && stoppedState.partsRead == 1 && stoppedState.yield.kept == stoppedKept)
print("now line: \(NowLine.sentence(of: stoppedState, machine: "Pip"))")

// MARK: A reading the app cancels

heading("A reading the app cancels in its second call")
let cancelled = try await readScriptedDay(replies: scriptedReplies, cancelling: [1])
let cancelledState = try fold(journal(of: cancelled))
let cancelledKept = cancelled.runs.reduce(0) { $0 + ($1.kept ?? 0) }
check("a cancelled reading is accepted", cancelledState.stop == .cancelled && cancelledState.isFinished)
check(
    "its yield is that of the saved part",
    cancelledState.partsRead == 1 && cancelledState.yield.kept == cancelledKept && cancelledKept == 2)
print("now line: \(NowLine.sentence(of: cancelledState, machine: "Pip"))")

// MARK: A cap over the limit

heading("305 open facts, and the cap shows 300")
let spec = HelperSpec.team
guard let lifecycle = spec.lifecycle else { fatalError("the team machine has no lifecycle") }
let capped = try await {
    let store = try Store(
        directory: FileManager.default.temporaryDirectory.appending(path: "run-journal-cap-\(UUID().uuidString)"),
        clock: { now })
    defer { try? FileManager.default.removeItem(at: store.directory) }
    let policy = CapturePolicy(switches: [.whatsapp: true], allowList: [.whatsapp: [scope]])
    try store.savePolicy(policy)
    let grant = policy.authorize(CaptureRequest(kind: .whatsapp, label: scope), at: now).grant!
    let hello = EvidenceSet(
        lines: [Evidence(id: 1, start: now, line: "Asha: hello", quotable: ["hello"])], context: ["members": ["Asha"]])
    let seed = try await HelperReader(spec: spec, model: RecordedModel(ByCall([reply([])]), store: store)).read(
        day: day, scope: scope, evidence: hello)
    let facts = (0..<RunSettings.standard.openFactsShown + 5).map { number in
        Item(
            task: spec.task, day: day, scope: scope, source: .whatsapp, citeFirst: 1, citeLast: 1, start: now, end: now,
            fields: [lifecycle.field: lifecycle.open[0], "text": "fact \(number)"], quote: "hello", run: seed.run!)
    }
    try store.saveReading(
        HelperReader.Result(items: facts, dropped: 0, run: nil), of: spec, day: day, scope: scope, grant: grant)
    let badItem = reply([item(cite: 1, quote: "words that are not in the line")])
    let reader = HelperReader(spec: spec, model: RecordedModel(ByCall([badItem]), store: store))
    let part = try await reader.read(
        day: day, scope: scope, evidence: hello, open: try store.queries.openItems(readBy: spec))
    try store.saveReading(part, of: spec, day: day, scope: scope, grant: grant)
    let runs = try store.queries.runs().filter { $0.id == part.run }
    return (part, runs, try store.queries.leftOut(of: part.run!))
}()
let cappedEvents =
    [RunEvent.started(lines: 1, parts: 1, promptHash: capped.1[0].prompt)]
    + RunEvent.events(of: capped.0, number: 1, lines: 1) + RunEvent.ending(runs: capped.1)
let cappedState = try fold(cappedEvents)
let capHits = cappedEvents.filter { if case .capHit = $0 { true } else { false } }
let beforeCapLine = cappedEvents.firstIndex(of: capHits[0])! + 1
print("now line: \(try nowLine(Array(cappedEvents.prefix(beforeCapLine))))")
check("the reader gives one cut of 5 open facts", capped.0.leftOut.contains(LeftOut(.openFacts, count: 5)))
check("the journal has one cap hit of 5 open facts", capHits == [.capHit(.openFacts, leftOut: 5)])
check(
    "the cut is not in the drops: the yield drops 1, and the reader stored 1",
    cappedState.yield == RunYield(kept: 0, dropped: 1) && capped.1[0].dropped == 1)
check(
    "the store keeps the same cut apart, under left_out",
    capped.2.contains(LeftOut(.openFacts, count: 5)))

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
