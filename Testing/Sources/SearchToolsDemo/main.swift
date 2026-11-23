import Foundation
import Kernel
import Lines
import Synchronization
import WorkbenchCore

// Shows each rule of the search tools twice: once where it holds a result back, once where it lets one through.
// One scratch store, synthetic lines only, no network.

final class Clock: Sendable {
    let now = Mutex(Date(timeIntervalSince1970: 1_795_000_000))
    var current: Date { now.withLock { $0 } }
    func advance(_ seconds: TimeInterval) { now.withLock { $0 = $0.addingTimeInterval(seconds) } }
}

struct StubModel: StructuredModel {
    let name = "stub"
    func generate<T: Decodable & Sendable>(_ type: T.Type, schema: JSONSchema, instructions: String, input: String)
        async throws -> ModelAnswer<T>
    {
        let reply = #"{"ok":true}"#
        return ModelAnswer(
            value: try JSONDecoder().decode(T.self, from: Data(reply.utf8)), model: name, usage: Usage(), reply: reply)
    }
}

struct Reply: Decodable, Sendable { let ok: Bool }

struct DemoError: Error { let reason: String }

nonisolated(unsafe) var failures = 0

func expect(_ claim: String, _ holds: Bool) {
    print("  \(holds ? "yes" : "NO ") \(claim)")
    if !holds { failures += 1 }
}

func need<T>(_ value: T?) throws -> T {
    guard let value else { throw DemoError(reason: "a value the demo needs is missing") }
    return value
}

func heading(_ text: String) { print("\n\(text)") }

func texts(_ lines: [FoundLine]) -> [String] { lines.map(\.text) }

let alice = try PersonID("alice")
let bob = try PersonID("bob")
let chatA = "111@g.us"
let chatB = "222@g.us"
let chatBob = "333@g.us"
let mailLabel = "Deals"
let thread = "thread-1"
let member = "91@s.whatsapp.net"
let secretWord = "zebraquartz"
let base: Int64 = 1_795_000_000_000

let clock = Clock()
let directory = FileManager.default.temporaryDirectory.appending(path: "search-tools-demo-\(UUID().uuidString)")

func openStore() throws -> Store { try Store(directory: directory, clock: { clock.current }) }

nonisolated(unsafe) var store = try openStore()
try store.savePolicy(
    CapturePolicy(
        switches: [.whatsapp: true, .mail: true],
        allowList: [.whatsapp: [chatA, chatB, chatBob], .mail: [mailLabel]]))

// MARK: Synthetic evidence

func at(_ seconds: Int64) -> UTCInstant { UTCInstant(milliseconds: base + seconds * 1000) }

func chatLine(_ text: String, _ stanza: String, chat: String, at seconds: Int64) throws -> ObservedLine {
    ObservedLine(
        line: Line(
            entity: try EntityKey.whatsAppGroup(chat: chat, author: .member(member), stanzaID: stanza), text: text,
            readerVersion: "demo 1"),
        eventTime: at(seconds), actor: member, messageRef: stanza)
}

func revoke(_ stanza: String, chat: String, at seconds: Int64) throws -> ObservedLine {
    ObservedLine(
        line: .tombstone(
            entity: try EntityKey.whatsAppGroup(chat: chat, author: .member(member), stanzaID: stanza),
            readerVersion: "demo 1"), eventTime: at(seconds), actor: member, messageRef: stanza)
}

func mailLine(_ text: String, _ id: String, at seconds: Int64) throws -> ObservedLine {
    ObservedLine(
        line: Line(
            entity: try EntityKey.web(site: "mail.google.com", container: thread, itemID: id), text: text,
            readerVersion: "demo 1"), eventTime: at(seconds), actor: "sender@example.com", messageRef: id)
}

func record(_ lines: [ObservedLine], chat: String, owner: PersonID) throws {
    let grant = try permission(.whatsapp, chat)
    _ = try store.record(
        SourceReading(
            grant: grant, label: chat, container: chat, audience: AudienceDigest(owner: "me", members: [member]),
            lines: lines, cursorAfter: nil, readerVersion: "demo 1"), of: .whatsAppChat, owner: owner)
}

func recordMail(_ lines: [ObservedLine]) throws {
    _ = try store.record(
        SourceReading(
            grant: try permission(.mail, mailLabel), label: mailLabel, container: thread,
            audience: AudienceDigest(owner: "me", members: ["sender@example.com"]), lines: lines, cursorAfter: nil,
            readerVersion: "demo 1"), of: .gmailMail, owner: alice)
}

func permission(_ kind: SourceKind, _ label: String) throws -> CaptureGrant {
    let decision = try store.currentPolicy().authorize(CaptureRequest(kind: kind, label: label), at: clock.current)
    guard let grant = decision.grant else { throw DemoError(reason: "no grant for \(label)") }
    return grant
}

func stored(_ text: String, in container: String) throws -> StoredLine {
    let all = try store.queries.currentLines(
        in: [container], from: Date(timeIntervalSince1970: 1_700_000_000),
        to: Date(timeIntervalSince1970: 1_900_000_000))
    guard let line = all.first(where: { $0.text == text }) else { throw DemoError(reason: "no line \(text)") }
    return line
}

func lineID(_ line: StoredLine) throws -> LineID {
    guard let id = LineID(bytes: Array(line.lineID)) else { throw DemoError(reason: "bad line id") }
    return id
}

// MARK: Runs and facts

func recordedRun(window: [StoredLine] = []) async throws -> RunID {
    try await RecordedModel(StubModel(), store: store).generate(
        Reply.self, schema: .object([.init("ok", .boolean)]), task: "demo", instructions: "demo", input: "demo input",
        holding: [.whatsapp], window: window.map { WindowLine(number: $0.number, lineID: $0.lineID) }
    ).run
}

nonisolated(unsafe) var spareRuns: [RunID] = []

func newRun() -> RunID { spareRuns.removeFirst() }

func context(_ reader: PersonID) -> ToolContext { ToolContext(run: newRun(), reader: reader) }

func windowSize(of run: RunID) -> Int { (try? store.queries.window(of: run).count) ?? -1 }

func windowTexts(of run: RunID) throws -> [String] { try store.queries.window(of: run).map(\.text) }

func addFact(_ spec: HelperSpec, _ fields: [String: String], citing lines: [StoredLine], chat: String) async throws {
    let run = try await recordedRun(window: lines)
    let numbers = lines.map(\.number)
    let item = Item(
        task: spec.task, day: WorkDay(containing: clock.current), scope: chat, source: .whatsapp,
        citeFirst: numbers.min() ?? 0, citeLast: numbers.max() ?? 0, start: clock.current, end: clock.current,
        fields: fields, quote: "q", run: run)
    try store.saveReading(
        HelperReader.Result(items: [item], dropped: 0, run: run), of: spec, day: item.day, scope: chat,
        grant: try permission(.whatsapp, chat))
}

func copies(of word: String) throws -> Int {
    try ["workbench.sqlite", "workbench.sqlite-wal"].reduce(0) { total, name in
        let data = (try? Data(contentsOf: directory.appending(path: name))) ?? Data()
        var found = 0
        var from = data.startIndex
        while let range = data.range(of: Data(word.utf8), in: from..<data.endIndex) {
            found += 1
            from = range.upperBound
        }
        return total + found
    }
}

// MARK: The scene

spareRuns = try await (0..<80).asyncMap { _ in try await recordedRun() }

try record(
    [
        try chatLine("invoice for Acme is overdue please pay", "a1", chat: chatA, at: 0),
        try chatLine("will send the invoice today", "a2", chat: chatA, at: 60),
        try chatLine("lunch plans tomorrow", "a3", chat: chatA, at: 120),
        try chatLine("contract signed by Acme", "a4", chat: chatA, at: 180),
        try chatLine("invoice paid", "a5", chat: chatA, at: 240),
        try chatLine("invoice reminder", "r2", chat: chatA, at: 480),
    ], chat: chatA, owner: alice)
try record(
    [try chatLine("bob aside about the invoice", "y1", chat: chatA, at: 150)], chat: chatA, owner: bob)
try record(
    [
        try chatLine("invoice Beta \(secretWord) pending approval", "b1", chat: chatB, at: 300),
        try chatLine("ok", "b2", chat: chatB, at: 360),
        try chatLine("invoice reminder", "r1", chat: chatB, at: 420),
        try chatLine("invoice invoice invoice", "t1", chat: chatB, at: 540),
    ], chat: chatB, owner: alice)
try record(
    [try chatLine("invoice invoice invoice invoice secret", "x1", chat: chatBob, at: 600)], chat: chatBob, owner: bob)
try recordMail([
    try mailLine("Acme invoice attached", "m1", at: 700), try mailLine("see the invoice terms", "m2", at: 760),
])
let oldMail = try stored("Acme invoice attached", in: thread)
clock.advance(60)
try recordMail([try mailLine("Acme invoice attached and corrected", "m1", at: 700)])

let followUps = try store.createMachine(from: .followUps, name: "Follow-ups").spec
let gammaMachine = try store.createMachine(from: .followUps, name: "Gamma").spec
let teamMachine = try store.createMachine(from: .team, name: "Team").spec
let a1 = try stored("invoice for Acme is overdue please pay", in: chatA)
let a2 = try stored("will send the invoice today", in: chatA)
let a4 = try stored("contract signed by Acme", in: chatA)
let b1 = try stored("invoice Beta \(secretWord) pending approval", in: chatB)
let y1 = try stored("bob aside about the invoice", in: chatA)
let x1 = try stored("invoice invoice invoice invoice secret", in: chatBob)

try await addFact(
    followUps, ["who": "Acme", "owes": "you", "kind": "promise", "text": "send the invoice to Acme"],
    citing: [a1, a2], chat: chatA)
try await addFact(
    followUps, ["who": "Acme", "owes": "them", "kind": "ask", "text": "countersign the contract"], citing: [a4],
    chat: chatA)
try await addFact(
    followUps, ["who": "Acme", "owes": "you", "kind": "ask", "text": "chase the late payment"], citing: [a1, y1],
    chat: chatA)
try await addFact(
    followUps, ["who": "Supplier", "owes": "you", "kind": "ask", "text": "pay the secret supplier"], citing: [x1],
    chat: chatBob)
try await addFact(
    followUps, ["who": "Beta", "owes": "you", "kind": "ask", "text": "approve the \(secretWord) invoice"],
    citing: [b1], chat: chatB)
try await addFact(
    gammaMachine, ["who": "Team", "owes": "you", "kind": "promise", "text": "gammaplan kickoff"], citing: [a4],
    chat: chatA)
try await addFact(
    teamMachine,
    ["person": "priyaverma", "project": "Falcon", "kind": "plan", "text": "ship the quarterly report"],
    citing: [a4], chat: chatA)
let aliceDay = Date(timeIntervalSince1970: 1_700_000_000)...Date(timeIntervalSince1970: 1_900_000_000)
print("Scene: 3 chats, 1 mail thread, 2 people (alice reads, bob is the second roster person), 7 facts.")

// MARK: Rule 1: audience

heading("Rule 1: a line or a fact is returned only when the Kernel path admits the reader")
let rule1 = context(alice)
let invoices = try store.searchLines("invoice", limit: 50, in: rule1)
expect(
    "alice finds her lines and none of bob's",
    invoices.count > 5 && !texts(invoices).contains { $0.contains("bob aside") || $0.contains("secret") })
let bobInvoices = try store.searchLines("invoice", limit: 50, in: context(bob))
expect(
    "bob finds exactly his two lines and none of alice's",
    Set(texts(bobInvoices)) == ["bob aside about the invoice", "invoice invoice invoice invoice secret"])
let top = try store.searchLines("invoice", limit: 1, in: context(alice))
expect(
    "a refused line takes no place in the limit: bob's best match ranks first, yet alice gets her own top line",
    texts(top) == ["invoice invoice invoice"])
let refusedRun = newRun()
let refused = try store.searchLines("secret", in: ToolContext(run: refusedRun, reader: alice))
expect("a search that finds only refused lines returns nothing", refused.isEmpty)
expect("and leaves no trace in the run window", try windowTexts(of: refusedRun).isEmpty)
let aliceFacts = try store.searchFacts("Acme", limit: 20, in: context(alice))
expect(
    "alice finds the facts whose cites she may read",
    Set(aliceFacts.map(\.title)) == ["send the invoice to Acme", "countersign the contract"])
let mixedRun = newRun()
expect(
    "a fact that cites one line she may not read is refused whole",
    try store.searchFacts("chase", in: ToolContext(run: mixedRun, reader: alice)).isEmpty)
expect("and its readable cite is not traced either", try windowTexts(of: mixedRun).isEmpty)
expect(
    "bob finds the fact on his own line",
    try store.searchFacts("supplier", in: context(bob)).map(\.title) == ["pay the secret supplier"])
expect(
    "alice does not find it", try store.searchFacts("supplier", in: context(alice)).isEmpty)

// MARK: Rule 2: trace

heading("Rule 2: every returned line is in run_window, and its number is the ordinal")
let traceRun = newRun()
let traceContext = ToolContext(run: traceRun, reader: alice)
let first = try store.searchLines("invoice", limit: 3, in: traceContext)
let window = try store.queries.window(of: traceRun)
expect(
    "the numbers of the found lines are the numbers of the run window",
    Set(first.map { Int64($0.number) }) == Set(window.map(\.number)) && window.count == 3)
let again = try store.searchLines("invoice", limit: 3, in: traceContext)
expect(
    "the same search again gives the same numbers and adds no row",
    again.map(\.number) == first.map(\.number) && windowSize(of: traceRun) == 3)
let next = try store.searchLines("contract", in: traceContext)
expect(
    "a new line takes the next number",
    next.map(\.number) == [(first.map(\.number).max() ?? 0) + 1] && windowSize(of: traceRun) == 4)
let factRun = newRun()
let traced = try store.searchFacts("invoice", in: ToolContext(run: factRun, reader: alice))
let factWindow = try store.queries.window(of: factRun)
expect(
    "the lines a fact cites are traced, under the numbers the fact shows",
    traced.flatMap(\.cites).allSatisfy { cite in factWindow.contains { $0.number == Int64(cite.number) } }
        && !traced.flatMap(\.cites).isEmpty)
let verify = try store.queries.window(of: traceRun).first { Int64(first[0].number) == $0.number }
expect("a cite number resolves to the line the model saw", verify?.text == first[0].text)

// MARK: Rule 5: read around a line

heading("Rule 5: neighbours are lines of the same container, by time, current versions, each checked")
let a3 = try stored("lunch plans tomorrow", in: chatA)
let around = try store.readLine(try lineID(a3), around: 1, in: context(alice))
expect(
    "alice reads a3 with one line each side; bob's line between a3 and a4 is skipped and the next takes its place",
    texts(around) == ["will send the invoice today", "lunch plans tomorrow", "contract signed by Acme"])
expect(
    "no line of another chat comes with it",
    try store.readLine(try lineID(a3), around: 20, in: context(alice)).allSatisfy { line in
        !texts([line]).contains { $0.contains("Beta") || $0 == "ok" }
    })
let currentMail = try stored("Acme invoice attached and corrected", in: thread)
let mail = try store.readLine(
    try lineID(try stored("see the invoice terms", in: thread)), around: 1, in: context(alice))
expect(
    "a mail neighbour is the current version of its message, not the old one",
    texts(mail) == ["Acme invoice attached and corrected", "see the invoice terms"])
let oldRead = try store.readLine(try lineID(oldMail), around: 1, in: context(alice))
expect(
    "reading the old version itself gives that version, and its own newer version is not a neighbour",
    texts(oldRead) == ["Acme invoice attached", "see the invoice terms"] && currentMail.lineID != oldMail.lineID)
let secretRun = newRun()
expect(
    "alice may not read bob's line: nothing comes back",
    try store.readLine(try lineID(y1), around: 2, in: ToolContext(run: secretRun, reader: alice)).isEmpty)
expect("and no trace", try windowTexts(of: secretRun).isEmpty)
expect(
    "bob reads it, and his neighbours that are alice's are skipped",
    texts(try store.readLine(try lineID(y1), around: 2, in: context(bob))) == ["bob aside about the invoice"])
expect(
    "a line that is not stored gives nothing",
    try store.readLine(
        try need(LineID(bytes: [UInt8](repeating: 7, count: 32))), around: 1, in: context(alice)
    ).isEmpty)

// MARK: Rule 6: ranking and time

heading("Rule 6: bm25 first, then newest; since and until filter on event time")
let ranked = texts(try store.searchLines("invoice", limit: 50, in: context(alice)))
print("  order: \(ranked.prefix(5).map { "\"\($0)\"" }.joined(separator: ", ")) ...")
let place = { (text: String) in ranked.firstIndex(of: text) ?? Int.max }
expect("more matches in a short line rank first", ranked.first == "invoice invoice invoice")
expect(
    "equal matches: newest first (r2 at 480 s, then r1 at 420 s, then a5 at 240 s)",
    ranked.filter { $0 == "invoice reminder" }.count == 2 && place("invoice paid") > place("invoice reminder"))
let sinceLines = try store.searchLines(
    "invoice", LineFilter(since: Date(timeIntervalSince1970: Double(base) / 1000 + 400)), limit: 50,
    in: context(alice))
expect(
    "since keeps only lines sent at or after it",
    !sinceLines.isEmpty
        && sinceLines.allSatisfy {
            ($0.eventTime ?? .distantPast) >= Date(timeIntervalSince1970: Double(base) / 1000 + 400)
        }
        && !texts(sinceLines).contains("will send the invoice today"))
let untilLines = try store.searchLines(
    "invoice", LineFilter(until: Date(timeIntervalSince1970: Double(base) / 1000 + 100)), limit: 50,
    in: context(alice))
expect(
    "until keeps only lines sent before it",
    Set(texts(untilLines)) == ["invoice for Acme is overdue please pay", "will send the invoice today"])
expect(
    "a source filter keeps mail only, and WhatsApp only",
    try store.searchLines("invoice", LineFilter(sources: [.mail]), limit: 50, in: context(alice)).allSatisfy {
        $0.source == .mail
    }
        && (try store.searchLines("invoice", LineFilter(sources: [.whatsapp]), limit: 50, in: context(alice)))
            .allSatisfy { $0.source == .whatsapp }
)
let factTime = clock.current
expect(
    "facts: since after their time finds none, since before it finds them",
    try store.searchFacts("Acme", FactFilter(since: factTime.addingTimeInterval(3600)), in: context(alice))
        .isEmpty
        && !(try store.searchFacts(
            "Acme", FactFilter(since: factTime.addingTimeInterval(-3600)), in: context(alice))).isEmpty
)
expect(
    "facts: until before their time finds none",
    try store.searchFacts("Acme", FactFilter(until: factTime.addingTimeInterval(-3600)), in: context(alice))
        .isEmpty)
expect(
    "facts: a task filter keeps the machine's facts, and a task that holds none finds none",
    try store.searchFacts("Acme", FactFilter(tasks: [followUps.task]), in: context(alice)).count == 2
        && (try store.searchFacts("Acme", FactFilter(tasks: [gammaMachine.task]), in: context(alice))).isEmpty
)
let promise = try need(aliceFacts.first { $0.title == "send the invoice to Acme" })
try store.close(item: promise.item, as: "kept", surface: .today)
let afterClose = try store.searchFacts("Acme", in: context(alice))
expect(
    "facts: a closed fact shows its outcome as its state",
    afterClose.first { $0.item == promise.item }?.state == "kept")
expect(
    "facts: openOnly leaves the closed fact out and keeps the open one",
    try store.searchFacts("Acme", FactFilter(openOnly: true), in: context(alice)).map(\.title) == [
        "countersign the contract"
    ])

// MARK: Rule 3: erased content never comes back

heading("Rule 3: erased, revoked or emptied content never comes back")
expect(
    "before the revoke, alice finds a5",
    texts(try store.searchLines("paid", in: context(alice))) == ["invoice paid"])
try record([try revoke("a5", chat: chatA, at: 240)], chat: chatA, owner: alice)
expect(
    "after the message is deleted for everyone, she does not",
    try store.searchLines("paid", in: context(alice)).isEmpty)
let eraseRun = newRun()
let beforeErase = try store.searchLines(secretWord, in: ToolContext(run: eraseRun, reader: alice))
let factBefore = try store.searchFacts(secretWord, in: context(alice))
let copiesBefore = try copies(of: secretWord)
expect(
    "before the erase, the line and the fact that cites it are found, and the word is in the file",
    beforeErase.count == 1 && factBefore.count == 1 && copiesBefore > 0)
expect("the run kept its text", try store.queries.runText(of: eraseRun) != nil)
try store.eraseEvidence(.grant(kind: .whatsapp, label: chatB))
expect("after the erase, no line is found", try store.searchLines(secretWord, in: context(alice)).isEmpty)
expect(
    "no fact is found: its quote and words were emptied",
    try store.searchFacts(secretWord, in: context(alice)).isEmpty
        && (try store.searchFacts("Beta", in: context(alice))).isEmpty)
expect(
    "the word is in no byte of the file or its log (copies: \(copiesBefore) -> \(try copies(of: secretWord)))",
    try copies(of: secretWord) == 0)
expect("the erase found the run: its text is gone", try store.queries.runText(of: eraseRun) == nil)
expect(
    "other chats are untouched",
    !(try store.searchLines("Acme", in: context(alice))).isEmpty)

// MARK: Rule 4: the index

heading("Rule 4: item_fts holds text fields and the title only; triggers and the one erase path keep it")
expect(
    "a text field is found (who: Acme, text: invoice)",
    try store.searchFacts("Acme", in: context(alice)).count == 2)
expect(
    "a choice value is not found (owes, kind: promise, ask)",
    try store.searchFacts("promise", in: context(alice)).isEmpty)
expect(
    "a member name and a label are not found (person: priyaverma, project: Falcon)",
    try store.searchFacts("priyaverma", in: context(alice)).isEmpty
        && (try store.searchFacts("Falcon", in: context(alice))).isEmpty)
expect(
    "the text of the same fact is found",
    try store.searchFacts("quarterly", in: context(alice)).map(\.title) == ["ship the quarterly report"])
expect("an insert is indexed", try store.searchFacts("gammaplan", in: context(alice)).count == 1)
try store.delete(.machine(gammaMachine.task))
expect("a delete of the item leaves no entry", try store.searchFacts("gammaplan", in: context(alice)).isEmpty)
expect(
    "an update that empties words leaves no entry (the erase above)",
    try store.searchFacts("Beta", in: context(alice)).isEmpty)

func sqlite(_ statements: String) throws -> String {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    process.arguments = [directory.appending(path: "workbench.sqlite").path, statements]
    process.standardOutput = output
    try process.run()
    process.waitUntilExit()
    return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

let followUpsMachine = "(SELECT id FROM machine WHERE task = '\(followUps.task)')"
_ = try sqlite(
    """
    INSERT INTO machine_change(machine_id, at, name, spec, state) SELECT machine_id, at, 'Follow-ups renamed', spec,
        state FROM machine_change WHERE id = (SELECT MAX(id) FROM machine_change WHERE machine_id = \(followUpsMachine));
    """)
expect(
    "a change that keeps the fields does not put a choice value in the index",
    try store.searchFacts("promise", in: context(alice)).isEmpty)
_ = try sqlite(
    """
    INSERT INTO machine_change(machine_id, at, name, spec, state) SELECT machine_id, at, name,
        json_set(spec, '$.fields[2].kind', json('{"text":{"required":false}}')), state FROM machine_change
        WHERE id = (SELECT MAX(id) FROM machine_change WHERE machine_id = \(followUpsMachine));
    """)
expect(
    "a spec change that makes a field free text reindexes the machine's old items",
    !(try store.searchFacts("promise", in: context(alice))).isEmpty)

let stepsRun = try need(Int(try sqlite("PRAGMA user_version;")))
_ = try sqlite(
    """
    DROP TRIGGER item_fts_insert; DROP TRIGGER item_fts_update; DROP TRIGGER item_fts_delete;
    DROP TRIGGER item_fts_respec; DROP TABLE item_fts;
    PRAGMA user_version = \(stepsRun - 1);
    """)
expect(
    "a store from before the step has no index: a search cannot run",
    (try? store.searchFacts("Acme", in: context(alice))) == nil)
store = try openStore()
expect(
    "opening it builds the index for the items that exist",
    try store.searchFacts("Acme", in: context(alice)).count == 2)

// MARK: openObject

heading("openObject: the object, its children and its facts, each fact checked, its cites traced")
let folder = try store.createWorkObject(type: ObjectTypes.folder, parent: nil, name: "Acme work")
let child = try store.createWorkObject(type: ObjectTypes.page, parent: folder.id, name: "Notes")
let gone = try store.createWorkObject(type: ObjectTypes.page, parent: folder.id, name: "Old notes")
try store.archive(gone.id)
let alicePromise = try need(try store.searchFacts("invoice Acme", in: context(alice)).first)
let bobFact = try need(try store.searchFacts("supplier", in: context(bob)).first)
try store.file(item: alicePromise.item, into: folder.id, how: .personMoved, surface: .machinePage)
try store.file(item: bobFact.item, into: folder.id, how: .personMoved, surface: .machinePage)
let openRun = newRun()
let opened = try need(try store.openObject(folder.id, in: ToolContext(run: openRun, reader: alice)))
expect(
    "the object comes with its type and name",
    opened.type == ObjectTypes.folder.id && opened.name == "Acme work" && !opened.archived)
expect(
    "its children come, the archived child does not",
    opened.children.map(\.name) == ["Notes"] && opened.children.first?.id == child.id)
expect(
    "a fact the reader may read comes, with its cites",
    opened.facts.map(\.item) == [alicePromise.item] && !(opened.facts.first?.cites.isEmpty ?? true))
expect(
    "a fact that cites a line the reader may not read does not come, and leaves no trace",
    !opened.facts.contains { $0.item == bobFact.item }
        && windowSize(of: openRun) == opened.facts.flatMap(\.cites).count)
let openWindow = try store.queries.window(of: openRun)
expect(
    "each cite's number is its place in the run window",
    opened.facts.flatMap(\.cites).allSatisfy { cite in openWindow.contains { $0.number == Int64(cite.number) } })
let asBob = try need(try store.openObject(folder.id, in: context(bob)))
expect("the other reader gets only their own fact", asBob.facts.map(\.item) == [bobFact.item])
expect(
    "an archived object opens by its own id",
    try store.openObject(gone.id, in: context(alice))?.archived == true)
expect("an unknown id gives nothing", try store.openObject("no-such-object", in: context(alice)) == nil)

try? FileManager.default.removeItem(at: directory)
print("\n\(failures == 0 ? "All rules shown both ways." : "\(failures) claim(s) failed.")")
exit(failures == 0 ? 0 : 1)

extension Sequence {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var results: [T] = []
        for element in self { results.append(try await transform(element)) }
        return results
    }
}
