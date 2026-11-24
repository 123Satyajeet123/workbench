import Foundation
import GRDB

struct Policy {
    let name: String
    /// F: the window is frozen when the row is planned. C: the window is chosen at claim.
    let frozenWindow: Bool
    /// C: no claim while a run of the same machine is calling or replied.
    let singleFlight: Bool
    /// C: consent and tombstone are checked inside the claim transaction.
    let checkAtClaim: Bool

    static let frozen = Policy(name: "F (D4 as written)", frozenWindow: true, singleFlight: false, checkAtClaim: true)
    static let claimTime = Policy(name: "C (86 s5)", frozenWindow: false, singleFlight: true, checkAtClaim: true)
    static let claimTimeNoCheck = Policy(
        name: "C, no claim check (control)", frozenWindow: false, singleFlight: true, checkAtClaim: false)
}

struct Metrics {
    var doubleReadLines = 0
    var doubledFactLines = 0
    var startsAfterRevoke = 0
    var waitingRowsAtRevoke = 0
    var plannedRowsAtWakeMax = 0
    var plannedRowsAtWakeTotal = 0
    var runsAfterWakeMax = 0
    var runsAfterWakeTotal = 0
    var maxParallelChildren = 0
    var maxParallelSameMachine = 0
    var drainMinutes: Double?
    var lostFacts = 0
    var totalRuns = 0
    var crashesFired = ""
}

/// One arm of the probe: a scheduler policy on its own temporary SQLite store.
final class Simulation {
    private let policy: Policy
    private let scenario: Scenario
    private let queue: DatabaseQueue
    private var crashes = CrashPlan.standard
    private var startCounts: [Int: Int] = [:]
    private var metrics = Metrics()
    private var nextLineID = 1

    init(policy: Policy, scenario: Scenario, directory: URL) throws {
        self.policy = policy
        self.scenario = scenario
        queue = try DatabaseQueue(path: directory.appendingPathComponent("\(UUID().uuidString).sqlite").path)
        try queue.write { db in
            try ProbeSchema.create(in: db)
            if policy.frozenWindow {
                try ProbeSchema.addDueKeyIndex(in: db)
            } else {
                try ProbeSchema.addPlannedUniqueIndex(in: db)
            }
            for source in 0..<Scenario.sources {
                try db.execute(sql: "INSERT INTO consent VALUES (?, 1)", arguments: [source])
            }
        }
    }

    func run() throws -> Metrics {
        var second = 0
        var drained = false
        while !drained && second < Scenario.wakeAt + 24 * 3_600 {
            if second == Scenario.activeEnd { second = Scenario.wakeAt }
            if second == Scenario.wakeAt { try recordPlannedRowsAtWake() }
            try step(at: second)
            drained = try second >= Scenario.wakeAt && isDrained()
            if drained { metrics.drainMinutes = Double(second - Scenario.wakeAt) / 60 }
            second += 1
        }
        try finish()
        return metrics
    }

    // MARK: One simulated second

    private func step(at second: Int) throws {
        try revokeIfDue(at: second)
        try insertArrivals(at: second)
        if try planFromTriggers(at: second) { return }
        if try finishCalls(at: second) { return }
        _ = try claim(at: second)
        try sampleParallelism()
    }

    private func revokeIfDue(at second: Int) throws {
        guard second == Scenario.revokeAt else { return }
        try queue.write { db in
            metrics.waitingRowsAtRevoke =
                try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM runs WHERE state='planned' AND machine % ? = ?",
                    arguments: [Scenario.sources, Scenario.revokedSource]) ?? 0
            try db.execute(sql: "UPDATE consent SET granted=0 WHERE source=?", arguments: [Scenario.revokedSource])
            try db.execute(sql: "UPDATE lines SET tombstone=1 WHERE source=?", arguments: [Scenario.revokedSource])
        }
    }

    private func insertArrivals(at second: Int) throws {
        let arriving = second == Scenario.wakeAt ? scenario.catchUp : scenario.bursts[second] ?? []
        try queue.write { db in
            for burst in arriving {
                let source = Scenario.source(of: burst.machine)
                let revoked = second >= Scenario.revokeAt && source == Scenario.revokedSource
                for _ in 0..<burst.count {
                    try db.execute(
                        sql: "INSERT INTO lines VALUES (?, ?, ?, ?, ?)",
                        arguments: [nextLineID, burst.machine, source, second, revoked ? 1 : 0])
                    nextLineID += 1
                }
            }
        }
    }

    /// Returns true when a crash happened and the step must end.
    private func planFromTriggers(at second: Int) throws -> Bool {
        var triggers: [(machine: Int, mode: String, cause: String, dueAt: Int)] = []
        if second % Scenario.tickSeconds == 0 {
            triggers += (0..<Scenario.machines).map { ($0, "sweep", "tick", second + Scenario.settleSeconds) }
        }
        triggers += (scenario.hints[second] ?? []).map { ($0, "now", "hint", second) }
        if second == Scenario.wakeAt {
            triggers += (0..<Scenario.machines).map { ($0, "now", "wake", second) }
        }
        for trigger in triggers {
            let inserted = try plan(
                machine: trigger.machine, mode: trigger.mode, cause: trigger.cause, dueAt: trigger.dueAt)
            if inserted && crashes.fires(.planned, at: second) {
                try recover()
                return true
            }
        }
        return false
    }

    // MARK: Plan, claim, finish

    /// Returns true when a new planned row was inserted.
    private func plan(machine: Int, mode: String, cause: String, dueAt: Int) throws -> Bool {
        try queue.write { db in
            guard try isConsented(db, machine: machine) else { return false }
            let unread = try unreadLines(db, machine: machine, honorTombstone: true)
            guard !unread.isEmpty else { return false }
            if policy.frozenWindow {
                return try planFrozen(db, machine: machine, mode: mode, cause: cause, dueAt: dueAt, window: unread)
            }
            let before = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM runs WHERE state='planned'") ?? 0
            try db.execute(
                sql: """
                    INSERT INTO runs(machine, mode, cause, due_at, state) VALUES (?, ?, ?, ?, 'planned')
                    ON CONFLICT(machine, mode) WHERE state='planned'
                    DO UPDATE SET cause=excluded.cause, due_at=min(due_at, excluded.due_at)
                    """,
                arguments: [machine, mode, cause, dueAt])
            return (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM runs WHERE state='planned'") ?? 0) > before
        }
    }

    private func planFrozen(
        _ db: Database, machine: Int, mode: String, cause: String, dueAt: Int, window: [Int]
    ) throws -> Bool {
        let key = "\(machine):" + window.map(String.init).joined(separator: ",")
        if let existing = try Int.fetchOne(
            db, sql: "SELECT id FROM runs WHERE due_key=? AND state='planned'", arguments: [key])
        {
            try db.execute(sql: "UPDATE runs SET due_at=min(due_at, ?) WHERE id=?", arguments: [dueAt, existing])
            return false
        }
        try db.execute(
            sql: "INSERT INTO runs(machine, mode, cause, due_at, state, due_key) VALUES (?, ?, ?, ?, 'planned', ?)",
            arguments: [machine, mode, cause, dueAt, key])
        let runID = db.lastInsertedRowID
        for line in window { try db.execute(sql: "INSERT INTO run_input VALUES (?, ?)", arguments: [runID, line]) }
        return true
    }

    /// Claims due rows up to the child cap. Returns true when a crash happened.
    private func claim(at second: Int) throws -> Bool {
        let due = try queue.read { db in
            try Row.fetchAll(
                db, sql: "SELECT id, machine FROM runs WHERE state='planned' AND due_at<=? ORDER BY due_at, id",
                arguments: [second])
        }
        for row in due {
            let calling = try queue.read {
                try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM runs WHERE state='calling'") ?? 0
            }
            if calling >= Scenario.childCap { return false }
            let started = try claimOne(runID: row["id"], machine: row["machine"], at: second)
            if started && crashes.fires(.calling, at: second) {
                try recover()
                return true
            }
        }
        return false
    }

    private func claimOne(runID: Int, machine: Int, at second: Int) throws -> Bool {
        try queue.write { db in
            if policy.singleFlight, try hasRunInFlight(db, machine: machine) { return false }
            if policy.checkAtClaim, !(try isConsented(db, machine: machine)) {
                try deleteRow(db, runID: runID)
                return false
            }
            if !policy.frozenWindow {
                let window = try unreadLines(db, machine: machine, honorTombstone: policy.checkAtClaim)
                if window.isEmpty {
                    try deleteRow(db, runID: runID)
                    return false
                }
                for line in window {
                    try db.execute(sql: "INSERT INTO run_input VALUES (?, ?)", arguments: [runID, line])
                }
            }
            let startCount = startCounts[machine, default: 0]
            startCounts[machine] = startCount + 1
            try db.execute(
                sql: "UPDATE runs SET state='calling', started_at=?, finish_at=? WHERE id=?",
                arguments: [second, second + Scenario.delay(machine: machine, startCount: startCount), runID])
            if second >= Scenario.revokeAt, Scenario.source(of: machine) == Scenario.revokedSource {
                metrics.startsAfterRevoke += 1
            }
            if second >= Scenario.wakeAt { metrics.runsAfterWakeTotal += 1 }
            return true
        }
    }

    /// The fake runner replies, then the reply is committed. Returns true when a crash happened.
    private func finishCalls(at second: Int) throws -> Bool {
        let finished = try queue.read { db in
            try Int.fetchAll(
                db, sql: "SELECT id FROM runs WHERE state='calling' AND finish_at<=? ORDER BY finish_at, id",
                arguments: [second])
        }
        for runID in finished {
            try queue.write { try $0.execute(sql: "UPDATE runs SET state='replied' WHERE id=?", arguments: [runID]) }
            if crashes.fires(.replied, at: second) {
                try recover()
                return true
            }
            try queue.write { try commit($0, runID: runID) }
            if crashes.fires(.committed, at: second) {
                try recover()
                return true
            }
        }
        return false
    }

    /// One fact per shown line that is still live. The unique key (run, line) makes a retry harmless.
    private func commit(_ db: Database, runID: Int) throws {
        try db.execute(
            sql: """
                INSERT OR IGNORE INTO facts(run_id, line_id)
                SELECT ri.run_id, ri.line_id FROM run_input ri JOIN lines l ON l.id=ri.line_id
                WHERE ri.run_id=? AND l.tombstone=0
                """,
            arguments: [runID])
        try db.execute(sql: "UPDATE runs SET state='committed' WHERE id=?", arguments: [runID])
    }

    // MARK: Restart recovery (D4 4.1 as the task states it)

    /// Children die. Replied runs commit. Calling runs go back to planned. Planned and committed stay.
    private func recover() throws {
        try queue.write { db in
            for runID in try Int.fetchAll(db, sql: "SELECT id FROM runs WHERE state='replied'") {
                try commit(db, runID: runID)
            }
            for row in try Row.fetchAll(db, sql: "SELECT id, machine, mode, due_at FROM runs WHERE state='calling'") {
                try replan(db, runID: row["id"], machine: row["machine"], mode: row["mode"], dueAt: row["due_at"])
            }
        }
    }

    private func replan(_ db: Database, runID: Int, machine: Int, mode: String, dueAt: Int) throws {
        if !policy.frozenWindow {
            try db.execute(sql: "DELETE FROM run_input WHERE run_id=?", arguments: [runID])
            let twin = try Int.fetchOne(
                db, sql: "SELECT id FROM runs WHERE machine=? AND mode=? AND state='planned'",
                arguments: [machine, mode])
            if let twin {
                try db.execute(sql: "UPDATE runs SET due_at=min(due_at, ?) WHERE id=?", arguments: [dueAt, twin])
                try db.execute(sql: "DELETE FROM runs WHERE id=?", arguments: [runID])
                return
            }
        }
        try db.execute(
            sql: "UPDATE runs SET state='planned', started_at=NULL, finish_at=NULL WHERE id=?", arguments: [runID])
    }

    // MARK: Shared queries

    private func isConsented(_ db: Database, machine: Int) throws -> Bool {
        try Int.fetchOne(
            db, sql: "SELECT granted FROM consent WHERE source=?", arguments: [Scenario.source(of: machine)]) == 1
    }

    private func hasRunInFlight(_ db: Database, machine: Int) throws -> Bool {
        try Int.fetchOne(
            db, sql: "SELECT 1 FROM runs WHERE machine=? AND state IN ('calling','replied') LIMIT 1",
            arguments: [machine]) != nil
    }

    /// Lines no live run (calling, replied, committed) has taken. Planned windows do not count as read.
    private func unreadLines(_ db: Database, machine: Int, honorTombstone: Bool) throws -> [Int] {
        try Int.fetchAll(
            db,
            sql: """
                SELECT id FROM lines WHERE machine=? AND (tombstone=0 OR ?=0) AND id NOT IN (
                    SELECT ri.line_id FROM run_input ri JOIN runs r ON r.id=ri.run_id
                    WHERE r.state IN ('calling','replied','committed')) ORDER BY id
                """,
            arguments: [machine, honorTombstone ? 1 : 0])
    }

    private func deleteRow(_ db: Database, runID: Int) throws {
        try db.execute(sql: "DELETE FROM run_input WHERE run_id=?", arguments: [runID])
        try db.execute(sql: "DELETE FROM runs WHERE id=?", arguments: [runID])
    }

    // MARK: Measurement

    private func recordPlannedRowsAtWake() throws {
        let perMachine = try queue.read { db in
            try Row.fetchAll(db, sql: "SELECT machine, COUNT(*) AS n FROM runs WHERE state='planned' GROUP BY machine")
        }
        metrics.plannedRowsAtWakeMax = perMachine.map { $0["n"] as Int }.max() ?? 0
        metrics.plannedRowsAtWakeTotal = perMachine.map { $0["n"] as Int }.reduce(0, +)
    }

    private func sampleParallelism() throws {
        let (total, sameMachine) = try queue.read { db in
            (
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM runs WHERE state='calling'") ?? 0,
                try Int.fetchOne(
                    db,
                    sql: "SELECT MAX(n) FROM (SELECT COUNT(*) AS n FROM runs WHERE state='calling' GROUP BY machine)")
                    ?? 0
            )
        }
        metrics.maxParallelChildren = max(metrics.maxParallelChildren, total)
        metrics.maxParallelSameMachine = max(metrics.maxParallelSameMachine, sameMachine)
    }

    private func isDrained() throws -> Bool {
        try queue.read { db in
            let open =
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM runs WHERE state IN ('planned','calling','replied')")
                ?? 0
            guard open == 0 else { return false }
            for machine in 0..<Scenario.machines where try isConsented(db, machine: machine) {
                if !(try unreadLines(db, machine: machine, honorTombstone: true)).isEmpty { return false }
            }
            return true
        }
    }

    private func finish() throws {
        metrics.crashesFired = crashes.fired.map { String($0.rawValue.prefix(2)) }.joined(separator: ",")
        try queue.read { db in
            metrics.doubleReadLines =
                try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(*) FROM (SELECT ri.line_id FROM run_input ri JOIN runs r ON r.id=ri.run_id
                        WHERE r.state='committed' GROUP BY ri.line_id HAVING COUNT(DISTINCT ri.run_id) > 1)
                        """) ?? 0
            metrics.doubledFactLines =
                try Int.fetchOne(
                    db, sql: "SELECT COUNT(*) FROM (SELECT line_id FROM facts GROUP BY line_id HAVING COUNT(*) > 1)")
                ?? 0
            metrics.lostFacts =
                try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(*) FROM lines l JOIN consent c ON c.source=l.source
                        WHERE l.tombstone=0 AND c.granted=1 AND NOT EXISTS (SELECT 1 FROM facts f WHERE f.line_id=l.id)
                        """) ?? 0
            metrics.totalRuns = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM runs WHERE state='committed'") ?? 0
            let perMachine = try Row.fetchAll(
                db,
                sql: "SELECT COUNT(*) AS n FROM runs WHERE started_at>=? GROUP BY machine", arguments: [Scenario.wakeAt]
            )
            metrics.runsAfterWakeMax = perMachine.map { $0["n"] as Int }.max() ?? 0
        }
    }
}
