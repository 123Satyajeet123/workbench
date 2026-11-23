import Foundation

/// A rule that times an open fact from the time it was opened: a fact of `task` whose `field` holds `value` that is
/// still open after `duration` is overdue for an answer. Data, not code (research 59, F-R5 §5.2).
public struct SLAPolicy: Sendable, Equatable {
    public var id: Int64
    /// The machine the policy is for.
    public var task: String
    /// The field of the machine's facts that it reads, such as "kind", and the value that it times, such as "question".
    public var field: String
    public var value: String
    public var duration: TimeInterval

    public init(id: Int64, task: String, field: String, value: String, duration: TimeInterval) {
        self.id = id
        self.task = task
        self.field = field
        self.value = value
        self.duration = duration
    }
}

/// What a fact tells the timers: the machine it is of, its fields, when it was opened and when it is due.
public struct TimerFact: Sendable, Equatable {
    public var task: String
    public var fields: [String: String]
    public var opened: Date
    public var due: Due?

    public init(task: String, fields: [String: String], opened: Date, due: Due?) {
        self.task = task
        self.fields = fields
        self.opened = opened
        self.due = due
    }
}

/// One time at which something should happen to one open fact.
public struct TimerRow: Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable {
        /// The fact's due time has come.
        case due
        /// A policy's time from the opening of the fact has run out.
        case sla
    }

    public var kind: Kind
    public var fireAt: Date
    public var zone: String
    public var source: Due.Source
    public var precision: TimeRecord.Precision
    public var policy: Int64?
}

/// How late a timer may fire, and how many may fire in one pass. Both are conventions that the port of openclaw's
/// catch-up limits starts with (research 59 §2); they are not measured for this app.
public struct TimerSettings: Sendable, Equatable {
    /// A timer later than this when it is found is skipped and left for the digest.
    public var staleAfter: TimeInterval = 2 * 86_400
    /// The most timers that fire in one pass: the rest wait for the next pass.
    public var catchUpLimit = 5

    public init() {}
}

public enum Timers {
    /// The timers an open fact has: one for its due time, and one for each policy of its machine that times it.
    /// Replaying a fact's events in any order gives the same rows. A fact with no due time has no due timer.
    public static func rows(of fact: TimerFact, policies: [SLAPolicy]) -> [TimerRow] {
        let due = fact.due.flatMap { due in
            due.utc.map {
                TimerRow(
                    kind: .due, fireAt: $0, zone: due.zone, source: due.source, precision: due.precision,
                    policy: nil)
            }
        }
        let zone = fact.due?.zone ?? TimeZone.current.identifier
        let sla = policies.filter { $0.task == fact.task && fact.fields[$0.field] == $0.value }.map {
            TimerRow(
                kind: .sla, fireAt: fact.opened.addingTimeInterval($0.duration), zone: zone, source: .default,
                precision: .none, policy: $0.id)
        }
        return (due.map { [$0] } ?? []) + sla
    }

    public enum Outcome: String, Sendable {
        case fired
        case skipStale = "skip_stale"
    }

    /// What to do at `now` with timers not yet decided, as (id, fire time) pairs: those whose time has come, oldest
    /// first. A timer found later than `staleAfter` is skipped. Of the others, only `catchUpLimit` fire.
    public static func decide(
        _ pending: [(id: Int64, fireAt: Date)], now: Date, settings: TimerSettings = TimerSettings()
    ) -> [(id: Int64, outcome: Outcome)] {
        var firing = 0
        return pending.filter { $0.fireAt <= now }.sorted { ($0.fireAt, $0.id) < ($1.fireAt, $1.id) }.compactMap {
            if now.timeIntervalSince($0.fireAt) > settings.staleAfter { return ($0.id, .skipStale) }
            guard firing < settings.catchUpLimit else { return nil }
            firing += 1
            return ($0.id, .fired)
        }
    }
}
