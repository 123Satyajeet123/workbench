import Foundation
import Kernel
import Lines
import Synchronization

@testable import WorkbenchCore

// The probe of the store safety step: what full sync costs, how long a check and a snapshot take, and whether an erase
// leaves a word in any backup. It uses synthetic stores in a temporary folder and deletes them. Every number is dev.
//
//   store-safety-probe
setvbuf(stdout, nil, _IOLBF, 0)
let scratch = FileManager.default.temporaryDirectory.appending(path: "store-safety-probe-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: scratch) }

func say(_ line: String) { print(line) }

nonisolated(unsafe) var failures: [String] = []
func check(_ passed: Bool, _ line: String) {
    say((passed ? "ok   " : "FAIL ") + line)
    if !passed { failures.append(line) }
}

func milliseconds(_ body: () throws -> Void) rethrows -> Double {
    let start = ContinuousClock.now
    try body()
    let elapsed = ContinuousClock.now - start
    return (Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18) * 1000
}

func percentile(_ sorted: [Double], _ fraction: Double) -> Double { sorted[Int(Double(sorted.count - 1) * fraction)] }
func format(_ value: Double) -> String { String(format: "%.3f", value) }

let clockNow = Mutex(Date(timeIntervalSince1970: 1_790_000_000))
func advance(days: Double) { clockNow.withLock { $0 = $0.addingTimeInterval(days * 86_400) } }
func openStore(_ folder: URL) throws -> Store { try Store(directory: folder, clock: { clockNow.withLock { $0 } }) }
func newStore(_ name: String) throws -> Store { try openStore(scratch.appending(path: name)) }
func size(of url: URL) throws -> Int { try FileManager.default.attributesOfItem(atPath: url.path)[.size] as! Int }

// 1. Write cost per transaction: the old settings (NORMAL, no full sync) against the store's settings as it opens.
func writeCost(_ name: String, oldSettings: Bool, transactions: Int) throws
    -> (setting: String, p50: Double, p95: Double)
{
    let store = try newStore(name)
    let setting = try store.writer.writeWithoutTransaction { db in
        if oldSettings {
            try db.execute(sql: "PRAGMA synchronous=NORMAL")
            try db.execute(sql: "PRAGMA fullfsync=OFF")
            try db.execute(sql: "PRAGMA checkpoint_fullfsync=OFF")
        }
        return try Int.fetchOne(db, sql: "PRAGMA synchronous") ?? -1
    }
    var times: [Double] = []
    for index in 0..<transactions {
        times.append(try milliseconds { try store.saveState("value \(index)", forKey: "probe.\(index % 50)") })
    }
    times.sort()
    return ("\(setting)", percentile(times, 0.5), percentile(times, 0.95))
}
for round in 0..<2 {
    for oldSettings in [true, false] {
        let cost = try writeCost("cost-\(round)-\(oldSettings)", oldSettings: oldSettings, transactions: 600)
        say(
            "write cost, 600 transactions, \(oldSettings ? "old: synchronous=NORMAL, fullfsync OFF" : "final: synchronous=FULL, fullfsync ON "), synchronous=\(cost.setting): p50 \(format(cost.p50)) ms, p95 \(format(cost.p95)) ms"
        )
    }
}
let settings = try newStore("settings").writer.writeWithoutTransaction { db in
    try ["synchronous", "fullfsync", "checkpoint_fullfsync", "secure_delete", "journal_size_limit"].map {
        try Int.fetchOne(db, sql: "PRAGMA \($0)") ?? -1
    }
}
check(settings == [2, 1, 1, 1, StoreDatabase.logSizeLimit], "the writer holds the final settings \(settings)")

// The pure rules.
check(
    SnapshotRules.date(ofFileName: SnapshotRules.fileName(at: clockNow.withLock { $0 })) == clockNow.withLock { $0 },
    "a snapshot name holds its date")
check(SnapshotRules.date(ofFileName: ".partial-1234") == nil, "a half-written name is no snapshot")
check(SnapshotRules.date(ofFileName: BackupFolder.preMigrationName) == nil, "the pre-migration copy is no snapshot")
check(SnapshotRules.isDue(newest: nil, now: Date()), "a snapshot is due when none exists")
check(
    !SnapshotRules.isDue(newest: Date(timeIntervalSince1970: 0), now: Date(timeIntervalSince1970: 23 * 3600)),
    "none is due at 23 hours")
check(
    SnapshotRules.isDue(newest: Date(timeIntervalSince1970: 0), now: Date(timeIntervalSince1970: 24 * 3600)),
    "one is due at 24 hours")

// 2. quick_check and VACUUM INTO on files of 50 MB and 500 MB.
func fill(_ store: Store, toMegabytes target: Int) throws {
    let text = String(repeating: "lorem ipsum dolor sit amet ", count: 75)
    var row = 0
    while try size(of: store.directory.appending(path: "workbench.sqlite")) < target * 1_000_000 {
        try store.writer.write { db in
            for _ in 0..<2000 {
                row += 1
                try db.execute(
                    sql: "INSERT INTO activity(ts, kind, app, bundle_id, title, document, text) VALUES (?,?,?,?,?,?,?)",
                    arguments: [
                        "2026-11-20T10:00:00Z", "text", "App", "app.bundle", "Title \(row)", nil, "\(row) " + text,
                    ])
            }
        }
        _ = try store.writer.writeWithoutTransaction { db in try db.checkpoint(.truncate) }
    }
}
let bigFolder = scratch.appending(path: "big")
for megabytes in [50, 500] {
    let building = try milliseconds { try fill(try openStore(bigFolder), toMegabytes: megabytes) } / 1000
    let store = try openStore(bigFolder)
    let check = try milliseconds { try store.checkIntegrity() }
    advance(days: 2)
    let snapshot = try milliseconds { try store.snapshotIfDue() }
    let fileMegabytes = try size(of: bigFolder.appending(path: "workbench.sqlite")) / 1_000_000
    say(
        "file \(fileMegabytes) MB (built in \(Int(building)) s): quick_check \(Int(check)) ms, VACUUM INTO \(Int(snapshot)) ms, snapshot \((store.snapshots().first?.bytes ?? 0) / 1_000_000) MB, snapshots kept \(store.snapshots().count)"
    )
}
try FileManager.default.removeItem(at: bigFolder)

// 3. Erase canary, both ways, through the one erase path.
let owner = try PersonID("owner-1")
func canary(_ name: String) -> String { "zxq\(name)canary\(UInt32.random(in: 100_000...999_999))" }
let (evidenceWord, revokedWord, activityWord, keptWord) = (
    canary("evidence"), canary("revoked"), canary("activity"), canary("kept")
)
let chats = ["chat-a@g.us", "chat-b@g.us", "chat-c@g.us"]
let policy = CapturePolicy(switches: [.whatsapp: true], allowList: [.whatsapp: Set(chats)])
let store = try newStore("canary")
try store.savePolicy(policy)
func line(_ text: String, stanza: String, chat: String) throws -> ObservedLine {
    ObservedLine(
        line: Line(
            entity: try EntityKey.whatsAppGroup(chat: chat, author: .member("91@s.whatsapp.net"), stanzaID: stanza),
            text: text, readerVersion: "probe 1"),
        eventTime: UTCInstant(milliseconds: 1_795_000_000_000), actor: "91@s.whatsapp.net", legacy: nil)
}
func tombstone(stanza: String, chat: String) throws -> ObservedLine {
    ObservedLine(
        line: .tombstone(
            entity: try EntityKey.whatsAppGroup(chat: chat, author: .member("91@s.whatsapp.net"), stanzaID: stanza),
            readerVersion: "probe 1"),
        eventTime: UTCInstant(milliseconds: 1_795_000_000_000), actor: "91@s.whatsapp.net", legacy: nil)
}
func read(_ lines: [ObservedLine], chat: String, row: Int64) throws {
    let now = clockNow.withLock { $0 }
    let grant = policy.authorize(CaptureRequest(kind: .whatsapp, label: chat), at: now).grant!
    try store.record(
        SourceReading(
            grant: grant, label: chat, container: chat,
            audience: AudienceDigest(owner: "me", members: ["91@s.whatsapp.net"]), lines: lines,
            cursorAfter: ScanCursor(storeID: "U1", lastRow: row, readAt: now), mapsLegacyRefs: false,
            readerVersion: "probe 1"),
        of: .whatsAppChat, owner: owner)
}
try read([try line(evidenceWord, stanza: "a", chat: chats[0])], chat: chats[0], row: 1)
try read([try line(keptWord, stanza: "b", chat: chats[1])], chat: chats[1], row: 1)
try read([try line(revokedWord, stanza: "c", chat: chats[2])], chat: chats[2], row: 1)
let activityID = try store.writer.write { db in
    try db.execute(
        sql: "INSERT INTO activity(ts, kind, app, bundle_id, title, document, text) VALUES (?,?,?,?,?,?,?)",
        arguments: ["2026-11-20T10:00:00Z", "text", "App", "app.bundle", "Title", nil, activityWord])
    return db.lastInsertedRowID
}

/// Copies of the word in every file under the store folder, the snapshots folder among them, with the file names.
func copies(of word: String, in folder: URL) -> [String: Int] {
    var found: [String: Int] = [:]
    let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])!
    for case let file as URL in files
    where (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
        let data = (try? Data(contentsOf: file)) ?? Data()
        var count = 0
        var from = data.startIndex
        while let range = data.range(of: Data(word.utf8), in: from..<data.endIndex) {
            count += 1
            from = range.upperBound
        }
        if count > 0 {
            found[
                file.resolvingSymlinksInPath().path.replacingOccurrences(
                    of: folder.resolvingSymlinksInPath().path + "/", with: "")] = count
        }
    }
    return found
}

func snapshotsOfADayEach(_ count: Int) throws {
    for _ in 0..<count {
        advance(days: 1.5)
        try store.snapshotIfDue()
        try store.snapshotIfDue()
    }
}
func noHits(_ word: String) -> Bool { copies(of: word, in: store.directory).isEmpty }
func hasPreMigrationCopy() -> Bool { FileManager.default.fileExists(atPath: store.backups.preMigrationCopy.path) }

try snapshotsOfADayEach(5)
check(store.snapshots().count == SnapshotRules.kept, "five days of hooks keep \(SnapshotRules.kept) snapshots")
try FileManager.default.copyItem(at: store.snapshots()[0].url, to: store.backups.preMigrationCopy)
for word in [evidenceWord, revokedWord, activityWord, keptWord] {
    check(!noHits(word), "before an erase \(word.prefix(12)) is in the backups too")
}

try store.eraseEvidence(.grant(kind: .whatsapp, label: chats[0]))
check(store.snapshots().isEmpty && !hasPreMigrationCopy(), "after eraseEvidence there is no backup")
check(noHits(evidenceWord), "after eraseEvidence the erased word has 0 hits in the store and snapshots folders")
try store.snapshotIfDue()
check(store.snapshots().count == 1, "the next hook makes one snapshot")
check(noHits(evidenceWord), "that snapshot holds no erased word")
let newest = store.snapshots().first!.url.lastPathComponent
check(
    (copies(of: keptWord, in: store.directory)["snapshots/" + newest] ?? 0) > 0, "the kept word is in the new snapshot")

try snapshotsOfADayEach(2)
try read([try tombstone(stanza: "c", chat: chats[2])], chat: chats[2], row: 2)
check(store.snapshots().isEmpty && noHits(revokedWord), "after a revoke in a read: no backup, 0 hits")
try snapshotsOfADayEach(3)
try store.delete(.activities(ActivityFilter(id: activityID)))
check(store.snapshots().isEmpty && noHits(activityWord), "after delete(.activities): no backup, 0 hits")
try store.snapshotIfDue()
check(
    store.snapshots().count == 1 && [evidenceWord, revokedWord, activityWord].allSatisfy(noHits),
    "the next hook makes one snapshot with no erased word")
check(!copies(of: keptWord, in: store.directory).isEmpty, "the kept word is still found")

advance(days: 2)
try store.snapshotIfDue()
let beforePrune = store.snapshots().map(\.url)
try store.delete(.everything(before: Date(timeIntervalSince1970: 1_000_000_000)))
check(beforePrune == store.snapshots().map(\.url), "a prune that removes nothing leaves the snapshots alone")

// 4. Time Machine exclusion, read back.
check(BackupFolder.isExcludedFromTimeMachine(store.directory), "the store folder is excluded from Time Machine")
check(BackupFolder.isExcludedFromTimeMachine(store.backups.url), "the snapshots folder is excluded from Time Machine")

// 5. A failed check stops writes; a restore puts a snapshot back.
let damagedFolder = scratch.appending(path: "damaged")
do {
    let healthy = try openStore(damagedFolder)
    try fill(healthy, toMegabytes: 5)
    try healthy.checkIntegrity()
    try healthy.saveState("still writable", forKey: "probe")
    check(true, "a healthy store passes its check and a write works")
    advance(days: 2)
    try healthy.snapshotIfDue()
}
let file = try FileHandle(forUpdating: damagedFolder.appending(path: "workbench.sqlite"))
try file.seek(toOffset: 2_000_000)
try file.write(contentsOf: Data(repeating: 0xFF, count: 40_000))
try file.close()
let damaged = try openStore(damagedFolder)
do {
    try damaged.checkIntegrity()
    check(false, "a damaged store must fail its check")
} catch {
    check(
        error.localizedDescription.contains("newest backup"),
        "a damaged store fails and names the newest backup: \(error.localizedDescription)")
}
do {
    try damaged.saveState("must fail", forKey: "probe")
    check(false, "a write to a damaged store must fail")
} catch {
    check(true, "a write to a damaged store fails: \(error.localizedDescription)")
}

let restoreFolder = scratch.appending(path: "restore")
var restoring: Store? = try openStore(restoreFolder)
try restoring?.saveState("one", forKey: "probe")
advance(days: 2)
try restoring?.snapshotIfDue()
try restoring?.saveState("two", forKey: "probe")
let snapshot = restoring!.snapshots()[0]
restoring = nil
try Store.restore(snapshot, into: restoreFolder)
let restored = try openStore(restoreFolder)
check(try restored.queries.state(forKey: "probe") == "one", "a restore puts the snapshot's value back")
check(
    FileManager.default.fileExists(atPath: restored.backups.preRestoreFolder.appending(path: "workbench.sqlite").path),
    "a restore keeps the replaced file in pre-restore")

// 6. The copy before a migration: kept when a step fails, deleted when the steps and the check pass.
let failingFolder = scratch.appending(path: "migration-fails")
do {
    let held = try openStore(failingFolder)
    try held.writer.writeWithoutTransaction { db in try db.execute(sql: "PRAGMA user_version = \(Schema.version - 2)") }
}
do {
    _ = try openStore(failingFolder)
    check(false, "a failing step must stop the open")
} catch let error as BackupError {
    let kept = FileManager.default.fileExists(atPath: BackupFolder(storeDirectory: failingFolder).preMigrationCopy.path)
    check(
        kept && error.localizedDescription.contains("pre-migration.sqlite"),
        "a failing step keeps the copy and says where")
}
let passingFolder = scratch.appending(path: "migration-passes")
try FileManager.default.createDirectory(at: passingFolder, withIntermediateDirectories: true)
let older = try StoreDatabase.open(at: passingFolder.appending(path: "workbench.sqlite"), busyTimeout: 10)
try Schema.open(older, through: Int(Schema.version) - 1)
check(
    try Schema.storedVersion(older) == Schema.version - 1,
    "an older store is made by the migration runner, one step short")
let migrated = try openStore(passingFolder)
check(
    try Schema.storedVersion(migrated.writer) == Schema.version
        && !FileManager.default.fileExists(atPath: migrated.backups.preMigrationCopy.path),
    "a passing migration runs the last step and deletes the copy")

if failures.isEmpty {
    say("ALL OK")
} else {
    for failure in failures { say("FAILED: \(failure)") }
    exit(1)
}
