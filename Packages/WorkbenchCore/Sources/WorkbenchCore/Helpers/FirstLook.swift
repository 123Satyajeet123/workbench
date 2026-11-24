import Foundation
import GRDB

/// The first look a new team takes at its own data: the last days of what its machines read, shown as the template's
/// main view. It is data over any template: what is shown follows the machine's spec.
public enum FirstLook {
    public static let defaultDays = 30

    /// The last `count` work days, oldest first, ending on `today`.
    public static func days(_ count: Int, endingOn today: WorkDay) -> [WorkDay] {
        (0..<max(count, 0)).reversed().map { today.adding(days: -$0) }
    }

    /// What the main view of a machine shows: for a machine with criteria, its items rated, best level first; for one whose
    /// facts open and close, the open ones; else every item, newest first.
    public static func shown(_ items: [Item], by spec: HelperSpec, at now: Date) -> [Item] {
        if spec.criteria != nil {
            let scored = items.map { (item: $0, triage: spec.triage(of: $0)) }
            return scored.sorted { left, right in
                (left.triage?.place ?? .max, -(left.triage?.points ?? 0)) < (
                    right.triage?.place ?? .max, -(right.triage?.points ?? 0)
                )
            }.map(\.item)
        }
        if let lifecycle = spec.lifecycle { return items.filter { $0.isOpen(in: lifecycle, at: now) } }
        return items.sorted { $0.start > $1.start }
    }
}

/// What a first look costs before it starts: the model calls it needs and what they come to.
public struct FirstLookCost: Sendable, Equatable {
    /// Dollars for one call before any run has measured it. A guess for the first estimate only.
    public static let firstGuessPerCallUSD = 0.02

    public var calls: Int
    public var perCallUSD: Double
    public var isMeasured: Bool

    public var totalUSD: Double { Double(calls) * perCallUSD }

    /// `measured` is the average cost of the runs of these tasks the store holds, when there are any.
    public init(calls: Int, measured: Double?) {
        self.calls = calls
        perCallUSD = measured ?? Self.firstGuessPerCallUSD
        isMeasured = measured != nil
    }
}

extension Queries {
    /// The average cost in dollars of one finished run of any of `tasks`; nil when none has finished with a cost.
    public func averageRunCost(ofTasks tasks: [String]) throws -> Double? {
        try reader.read { db in
            try Double.fetchOne(
                db,
                sql: """
                    SELECT AVG(cost_usd) FROM run WHERE outcome = 'done' AND cost_usd > 0
                        AND task IN (SELECT value FROM json_each(?))
                    """, arguments: [try Coding.json(tasks)])
        }
    }
}
