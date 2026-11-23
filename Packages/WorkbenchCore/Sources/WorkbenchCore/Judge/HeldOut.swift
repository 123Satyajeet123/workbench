import Foundation

/// Which use a product's marks may serve. Written once, when the product is made, and never recomputed.
public enum SplitRole: String, Codable, Sendable, CaseIterable {
    case dev
    case heldOut = "held_out"

    /// The founder's study window: every product of these days is held out, whatever the date hash says.
    public static let studyWindow: ClosedRange<WorkDay> = WorkDay("2026-11-23")!...WorkDay("2026-12-06")!

    /// A task's held-out window: the days after a freeze, for `windowDays` days.
    public init(day: WorkDay, freezes: [Freeze]) {
        let inFreezeWindow = freezes.contains { $0.window.contains(day) }
        if Self.studyWindow.contains(day) || inFreezeWindow {
            self = .heldOut
        } else {
            self = EvalSplit(day) == .heldOut ? .heldOut : .dev
        }
    }
}

/// The parts of a judge and a writer, frozen and hashed. A change to any part is a new freeze with a new window and no
/// certificate. A held-out window starts the day after the freeze.
public struct Freeze: Sendable, Equatable {
    public var hash: String
    public var taskType: String
    public var frozenAt: Date
    public var windowDays: Int
    public var parts: JudgeVersions

    public init(taskType: String, frozenAt: Date, windowDays: Int, parts: JudgeVersions) {
        hash = parts.hash
        self.taskType = taskType
        self.frozenAt = frozenAt
        self.windowDays = windowDays
        self.parts = parts
    }

    /// The days of the held-out window.
    public var window: ClosedRange<WorkDay> {
        let first = WorkDay(containing: frozenAt).adding(days: 1)
        return first...first.adding(days: windowDays - 1)
    }

    public static let defaultWindowDays = 14
}

/// What a piece of code does with rows. Learning, tuning and error analysis are refused held-out rows. Only an
/// evaluation of one freeze reads them, and only once per freeze.
public enum DataUse: Sendable, Equatable {
    case learning
    case tuning
    case errorAnalysis
    case evaluation(freeze: String)
}

public enum HeldOutRefusal: Error, Equatable, CustomStringConvertible {
    case notForLearning(DataUse)
    case alreadyReported(freeze: String)
    case unknownFreeze(String)
    case rungFrozen(String)

    public var description: String {
        switch self {
        case .notForLearning: "Held-out rows are not read for learning, tuning or error analysis."
        case .alreadyReported: "This version already has its held-out number. A second look makes the days dev."
        case .unknownFreeze: "No frozen version has this hash."
        case .rungFrozen: "A held-out window is open for this task, so its rung does not change."
        }
    }
}

/// The one gate every read of products and marks for learning passes. Both directions are code: a dev read is
/// allowed for every use, and a held-out read is refused for every use but an evaluation.
public enum HeldOutGuard {
    public static func admit(_ role: SplitRole, for use: DataUse) throws {
        guard role == .heldOut else { return }
        guard case .evaluation = use else { throw HeldOutRefusal.notForLearning(use) }
    }
}

extension Store {
    /// Freezes the parts of a judge for a task. The held-out window of the task starts the day after.
    @discardableResult
    public func freeze(
        _ parts: JudgeVersions, taskType: String, windowDays: Int = Freeze.defaultWindowDays
    ) throws -> Freeze {
        let freeze = Freeze(taskType: taskType, frozenAt: clock(), windowDays: windowDays, parts: parts)
        try writer.write { db in
            try db.execute(
                sql:
                    "INSERT OR IGNORE INTO judge_freeze(hash, task_type, frozen_at, window_days, parts) VALUES (?,?,?,?,?)",
                arguments: [freeze.hash, taskType, freeze.frozenAt.stored, windowDays, try Coding.json(parts.parts)])
        }
        return try queries.freezes(of: taskType).first { $0.hash == freeze.hash } ?? freeze
    }

    /// Records the held-out numbers of one frozen version. The first report stands; a second is refused.
    public func reportHeldOut(freeze hash: String, numbers: [String: Double]) throws {
        try writer.write { db in
            guard try Int.fetchOne(db, sql: "SELECT 1 FROM judge_freeze WHERE hash = ?", arguments: [hash]) != nil
            else { throw HeldOutRefusal.unknownFreeze(hash) }
            guard
                try Int.fetchOne(db, sql: "SELECT 1 FROM heldout_report WHERE hash = ?", arguments: [hash]) == nil
            else { throw HeldOutRefusal.alreadyReported(freeze: hash) }
            try db.execute(
                sql: "INSERT INTO heldout_report(hash, reported_at, numbers) VALUES (?,?,?)",
                arguments: [hash, clock().stored, try Coding.json(numbers)])
        }
    }
}

extension Queries {
    /// The freezes of a task, oldest first.
    public func freezes(of taskType: String) throws -> [Freeze] {
        try reader.read { db in
            try db.fetch(
                "judge_freeze",
                "SELECT hash, frozen_at, window_days, parts FROM judge_freeze WHERE task_type = ? ORDER BY frozen_at, hash",
                [taskType]
            ) { row in
                Freeze(
                    taskType: taskType, frozenAt: try row.date("frozen_at"), windowDays: try row.value("window_days"),
                    parts: JudgeVersions(parts: try row.json("parts")))
            }
        }
    }

    /// Whether a task's held-out window is open on `day`.
    public func heldOutWindowIsOpen(of taskType: String, on day: WorkDay) throws -> Bool {
        try freezes(of: taskType).contains { $0.window.contains(day) }
    }
}
