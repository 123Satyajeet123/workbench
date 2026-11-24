import Foundation
import GRDB

@testable import WorkbenchCore

// Probe R2 (research 86 review §6): the erase of one chat of 10,000 lines on a synthetic store of 10x an assumed dev
// size. Every number is dev (synthetic). The rule is written in GATES.md before the run: p95 of the erase over 1.0 s, or
// edges per fact (mean or p95) over 20, means the range edges must be cut.
//
//   provenance-probe
setvbuf(stdout, nil, _IOLBF, 0)
let scratch = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appending(
    path: ".build/provenance-probe-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: scratch) }

let chatCount = 100
let linesPerChat = 10_000
let linesPerRun = 100
let factsPerRun = 2
let erasedChats = 10
let widths = [1, 1, 1, 1, 1, 2, 2, 2, 3, 5, 5, 10, 10, 40, 1, 2, 1, 2, 3, 1]

func chatLabel(_ chat: Int) -> String { "chat\(chat)@g.us" }
func counted(_ prefix: String, _ number: Int, size: Int) -> Data {
    var data = Data(prefix.utf8)
    withUnsafeBytes(of: UInt64(number).bigEndian) { data.append(contentsOf: $0) }
    return data + Data(repeating: 0, count: max(0, size - data.count))
}

func build(_ store: Store) throws {
    let now = "2026-11-20T10:00:00Z"
    try store.writer.write { db in
        let evidence = try db.cachedStatement(
            sql: """
                INSERT INTO evidence(line_id, entity_key, quality, source_id, container, event_time, first_seen,
                    last_seen, actor, text, message_ref, tombstone, label_id, grant_id, audience_digest, retention_class,
                    obtained_by, reader_version) VALUES (?,?,'stable',?,?,?,?,?,'a',?,?,0,?,?,?,'r','db','p')
                """)
        let run = try db.cachedStatement(
            sql: """
                INSERT INTO run(task, model, prompt, input_bytes, input_sha, started_at, ended_at, outcome)
                VALUES ('probe.machine','m','p',8000,'s',?,?,'done')
                """)
        let text = try db.cachedStatement(
            sql: "INSERT INTO run_text(run_id, input, reply, kinds) VALUES (?,?,?,'[\"whatsapp\"]')")
        let window = try db.cachedStatement(sql: "INSERT INTO run_window(run_id, ordinal, line_id) VALUES (?,?,?)")
        let item = try db.cachedStatement(
            sql: """
                INSERT INTO item(task, run_id, day, scope, source, cite_first, cite_last, start_at, end_at, fields, quote,
                    created_at, quote_line, quote_part, quote_start, quote_end, label, authority)
                VALUES ('probe.machine',?,'2026-11-20',?,'whatsapp',?,?,?,?,?,?,?,?,0,0,5,NULL,'unknown')
                """)
        let event = try db.cachedStatement(
            sql: """
                INSERT INTO item_event(item_id, kind, line_id, quote, valid_at, recorded_at, run_id, actor)
                VALUES (?, 'restate', ?, 'event words', ?, ?, ?, 'model')
                """)
        let summary = try db.cachedStatement(
            sql: """
                INSERT INTO summary(day, task, field, scope, fingerprint, kinds, body, saved_at)
                VALUES ('2026-11-20','probe.machine','who',?,'f','["whatsapp"]',?,?)
                """)
        var lineNumber = 0
        var factNumber = 0
        for chat in 0..<chatCount {
            let label = chatLabel(chat)
            let grant = Store.grantID(kind: .whatsapp, label: label)
            var lineIDs: [Data] = []
            for offset in 0..<linesPerChat {
                lineNumber += 1
                let lineID = counted("line", lineNumber, size: 32)
                lineIDs.append(lineID)
                try evidence.execute(
                    arguments: [
                        lineID, counted("entity", lineNumber, size: 40), Data(repeating: 1, count: 16), label,
                        1_795_000_000_000 + lineNumber, 1_795_000_000_000, 1_795_000_000_000,
                        "Asha: please send the deck by Friday \(lineNumber) \(String(repeating: "word ", count: 8))",
                        "m\(offset)", Data(repeating: 2, count: 16), grant, Data(repeating: 3, count: 32),
                    ])
            }
            var runIDs: [Int64] = []
            for first in stride(from: 0, to: linesPerChat, by: linesPerRun) {
                try run.execute(arguments: [now, now])
                let runID = db.lastInsertedRowID
                runIDs.append(runID)
                try text.execute(arguments: [runID, String(repeating: "x", count: 8000), "reply"])
                for ordinal in 1...linesPerRun {
                    try window.execute(arguments: [runID, ordinal, lineIDs[first + ordinal - 1]])
                }
                for _ in 0..<factsPerRun {
                    factNumber += 1
                    let width = widths[factNumber % widths.count]
                    let citeFirst = 1 + (factNumber * 7) % (linesPerRun - width)
                    let who = "p\(chat)-\(factNumber % 5)"
                    try item.execute(
                        arguments: [
                            runID, label, citeFirst, citeFirst + width - 1, now, now, "{\"who\":\"\(who)\"}",
                            "send the deck", now, citeFirst,
                        ])
                    let itemID = db.lastInsertedRowID
                    if factNumber % 10 == 0 {
                        try event.execute(arguments: [itemID, citeFirst, now, now, runID])
                    }
                }
            }
            for who in 0..<5 {
                try summary.execute(arguments: [
                    "who: p\(chat)-\(who)", "{\"scope\":\"x\",\"details\":[],\"run\":\(runIDs[0])}", now,
                ])
            }
        }
    }
}

func seconds(_ body: () throws -> Void) rethrows -> Double {
    let start = ContinuousClock.now
    try body()
    let elapsed = ContinuousClock.now - start
    return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
}

/// The nearest-rank percentile: for ten samples the 95th is the largest.
func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
    sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int((fraction * Double(sorted.count)).rounded(.up)) - 1)]
}

func format(_ value: Double) -> String { String(format: "%.3f", value) }

let store = try Store(directory: scratch.appending(path: "store"))
let built = try seconds { try build(store) }
let stats = try store.writer.read { db in
    (
        lines: try Int.fetchOne(db, sql: "SELECT count(*) FROM evidence") ?? 0,
        runs: try Int.fetchOne(db, sql: "SELECT count(*) FROM run") ?? 0,
        facts: try Int.fetchOne(db, sql: "SELECT count(*) FROM item") ?? 0,
        events: try Int.fetchOne(db, sql: "SELECT count(*) FROM item_event") ?? 0,
        windowRows: try Int.fetchOne(db, sql: "SELECT count(*) FROM run_window") ?? 0
    )
}
print(
    "store: \(stats.lines) lines, \(stats.runs) runs, \(stats.facts) facts, \(stats.events) events, \(stats.windowRows) window rows; built in \(format(built)) s"
)

var batchTimes: [Double] = []
let backfill = try seconds {
    // The hourly hook runs slices of 20 s and ends each with a passive checkpoint.
    var sliceStart = ContinuousClock.now
    while try !store.provenanceBackfillIsComplete() {
        batchTimes.append(try seconds { try store.backfillBatch(size: 500) })
        if ContinuousClock.now - sliceStart > .seconds(20) {
            try store.checkpointPassively()
            sliceStart = ContinuousClock.now
        }
    }
    try store.checkpointPassively()
}
batchTimes.sort()
print(
    "backfill: \(format(backfill)) s in \(batchTimes.count) batches of 500; batch p50 \(format(percentile(batchTimes, 0.5))) s, p95 \(format(percentile(batchTimes, 0.95))) s, max \(format(batchTimes.last ?? 0)) s"
)

let edgesPerFact = try store.writer.read { db in
    try Int.fetchAll(
        db,
        sql: """
            SELECT count(*) FROM derivation WHERE node_kind = 'item' AND from_kind = 'line'
            GROUP BY node_id ORDER BY 1
            """)
}
let mean = Double(edgesPerFact.reduce(0, +)) / Double(max(1, edgesPerFact.count))
let edgeP95 = percentile(edgesPerFact.map(Double.init), 0.95)
let totals = try store.writer.read { db in
    (
        edges: try Int.fetchOne(db, sql: "SELECT count(*) FROM derivation") ?? 0,
        inputs: try Int.fetchOne(db, sql: "SELECT count(*) FROM run_input") ?? 0,
        bytes:
            (try? FileManager.default.attributesOfItem(
                atPath: store.directory.appending(path: "workbench.sqlite").path)[.size] as? Int) ?? 0
    )
}
print(
    "edges: \(totals.edges) rows, \(totals.inputs) run_input rows, file \(totals.bytes / 1_000_000) MB; edges per fact from lines (supports + quotes): mean \(format(mean)), p95 \(format(edgeP95)), max \(edgesPerFact.last ?? 0)"
)

var previewTimes: [Double] = []
var oldTimes: [Double] = []
var eraseTimes: [Double] = []
var transactionTimes: [Double] = []
var finishTimes: [Double] = []
var steps: [Double] = []
for chat in 0..<erasedChats {
    let selection = LineSelection(
        sql: "SELECT line_id FROM evidence WHERE container = ?", arguments: [chatLabel(chat)])
    var old = OldJoinReach()
    var closure: EraseClosure?
    oldTimes.append(try seconds { old = try store.writer.read { try Store.oldJoinReach(of: selection, in: $0) } })
    previewTimes.append(try seconds { closure = try store.writer.read { try Store.closure(of: selection, in: $0) } })
    let counts = try store.previewEvidenceErasure(.grant(kind: .whatsapp, label: chatLabel(chat)))
    let erasure = EvidenceErasure.grant(kind: .whatsapp, label: chatLabel(chat))
    transactionTimes.append(
        try seconds {
            _ = try store.writeCountingChanges { db in
                // The steps of `eraseEvidence`, timed one by one.
                let grant = Store.grantID(kind: .whatsapp, label: chatLabel(chat))
                let lines = LineSelection(sql: "SELECT line_id FROM evidence WHERE grant_id = ?", arguments: [grant])
                steps.append(try seconds { try Store.eraseCopies(of: lines, in: db) })
                steps.append(
                    try seconds { try db.execute(sql: "DELETE FROM evidence WHERE grant_id = ?", arguments: [grant]) })
                steps.append(try seconds { try EvidenceStamp.dropOrphanStructure(in: db) })
            }
        })
    print(
        "chat \(chat) transaction: redact copies \(format(steps[0])) s, delete lines \(format(steps[1])) s, orphan structure \(format(steps[2])) s"
    )
    steps = []
    var phases: [Double] = []
    finishTimes.append(
        try seconds {
            try store.backupLock.withLock {
                phases.append(try seconds { try store.backups.removeEverything() })
                phases.append(try seconds { try store.truncateLog() })
            }
        })
    print(
        "chat \(chat) finishErase: backups \(format(phases[0])) s, log truncate \(format(phases[1])) s"
    )
    eraseTimes.append(transactionTimes[chat] + finishTimes[chat])
    if chat == 0 || chat == erasedChats - 1 {
        let reached = closure!
        print(
            "chat \(chat): lines \(counts.lines); closure reaches \(reached.reached.count - reached.lines.count) nodes: \(reached.items.count) facts, \(reached.ids(ofKind: .itemEvent).count) events, \(reached.ids(ofKind: .summary).count) summaries, \(reached.ids(ofKind: .run).count) runs; old joins reach \(old.items.count) facts, \(old.events.count) events, \(old.summaries.count) summaries, \(old.runs.count) runs; old facts not in closure: \(Set(old.items).subtracting(reached.items).count)"
        )
    }
}
func summary(_ name: String, _ times: [Double]) {
    let sorted = times.sorted()
    print(
        "\(name) over \(times.count) chats: p50 \(format(percentile(sorted, 0.5))) s, p95 \(format(percentile(sorted, 0.95))) s, max \(format(sorted.last ?? 0)) s"
    )
}
summary("closure (pass 1 and 2, read only)", previewTimes)
summary("old joins (read only)", oldTimes)
summary("transaction of the erase (closure, redaction, delete of lines, search optimize)", transactionTimes)
summary("finishErase (backups, log, optimize)", finishTimes)
summary("full erase of 10,000 lines (transaction and finishErase, closure only)", eraseTimes)
print("erase times in order: " + eraseTimes.map(format).joined(separator: " "))
let eraseP95 = percentile(eraseTimes.sorted(), 0.95)
let overBudget = eraseP95 > 1.0 || mean > 20 || edgeP95 > 20
print(
    "rule: erase p95 \(format(eraseP95)) s (limit 1.0), edges per fact mean \(format(mean)) and p95 \(format(edgeP95)) (limit 20): \(overBudget ? "OVER: cut the range edges" : "WITHIN the rule")"
)
