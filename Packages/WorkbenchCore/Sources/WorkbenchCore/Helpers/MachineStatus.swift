import Foundation

/// What the caller alone knows about the source of a machine: whether it may read now.
public enum SourceStanding: Sendable, Equatable {
    case ready
    /// The switch of its kind of source is off.
    case off
    /// The source is on, and nothing is chosen for the machine to read.
    case nothingChosen
}

/// A reason a machine makes no model call now. The reasons about the model are those of `ModelBlock`.
public enum NotReading: Sendable, Equatable {
    case pausedByPerson
    case sourceOff
    case nothingChosen
    case model(ModelBlock)
}

/// What a machine did before now, as its journals and runs say.
public enum ReadingHistory: Sendable, Equatable {
    /// The last reading that finished with no failure and no cancel, and what it kept and dropped.
    case finished(LastRead)
    /// A reading has a journal, and none finished clean.
    case notFinished
    /// The machine made model calls, and no reading has a journal: they were made before readings were recorded, or
    /// by a source that reads in its own way.
    case unrecorded(lastCall: Date)
    case never
}

public struct LastRead: Sendable, Equatable {
    public var at: Date
    public var yield: RunYield
}

/// The newest journal of a machine, folded.
public struct LatestReading: Sendable, Equatable {
    public var journal: StoredJournal
    public var state: RunState
    /// What `NowLine` says of the journal's last event.
    public var nowLine: String
}

/// What a machine can say of itself, from stored facts only: what it is doing, when it last read, why it does not read,
/// and when it reads next.
public struct MachineStatus: Sendable, Equatable {
    /// The newest reading with a journal; nil when no reading has one.
    public var latest: LatestReading?
    public var history: ReadingHistory
    /// Why no model call starts now, the one that stops it first at the head. Empty when it can read.
    public var notReading: [NotReading]
    /// When the schedule starts the next reading. Nil when the schedule is off or the machine does not read.
    public var nextReading: Date?
    /// The one sentence for the page: `NowLine` over the typed parts above.
    public var sentence: String

    public var lastRead: LastRead? {
        if case .finished(let last) = history { last } else { nil }
    }
}

extension Queries {
    /// The status of `machine` at `now`. `model` is the model it would read with, nil when none is installed, and
    /// `source` is what the machine's source says. Dates in the sentence are in `zone`.
    public func status(
        of machine: Machine, model: (any StructuredModel)?, source: SourceStanding, now: Date, zone: TimeZone
    ) throws -> MachineStatus {
        let task = machine.task
        let latest = try latestJournal(of: task).map { journal -> LatestReading in
            let state = try journal.state(of: task)
            return LatestReading(
                journal: journal, state: state, nowLine: NowLine.sentence(of: state, machine: machine.name))
        }
        let history = try history(of: task)
        let notReading = notReading(machine, model: model, source: source, now: now)
        let nextReading = notReading.isEmpty ? try nextReading(of: machine, now: now, zone: zone) : nil
        return MachineStatus(
            latest: latest, history: history, notReading: notReading, nextReading: nextReading,
            sentence: NowLine.sentence(
                machine: machine.name, notReading: notReading, latest: latest?.state, history: history,
                nextReading: nextReading, now: now, zone: zone))
    }

    private func history(of task: String) throws -> ReadingHistory {
        if let clean = try latestCleanJournal(of: task), let at = clean.ended {
            return .finished(LastRead(at: at, yield: try clean.state(of: task).yield))
        }
        if try latestJournal(of: task) != nil { return .notFinished }
        return try lastCall(of: task).map { .unrecorded(lastCall: $0) } ?? .never
    }

    private func notReading(
        _ machine: Machine, model: (any StructuredModel)?, source: SourceStanding, now: Date
    ) -> [NotReading] {
        var reasons: [NotReading] = []
        if machine.state == .paused { reasons.append(.pausedByPerson) }
        switch source {
        case .ready: break
        case .off: reasons.append(.sourceOff)
        case .nothingChosen: reasons.append(.nothingChosen)
        }
        if let block = modelBlock(for: model, at: now) { reasons.append(.model(block)) }
        return reasons
    }

    private func nextReading(of machine: Machine, now: Date, zone: TimeZone) throws -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return try watchSchedule(of: machine.task, source: machine.spec.source)
            .nextRun(after: try lastScheduledRead(of: machine.task), now: now, calendar: calendar)
    }
}

extension StoredJournal {
    /// The journal folded. A journal that is not one is an error of the store, said with the task it belongs to.
    func state(of task: String) throws -> RunState {
        do {
            return try RunState.fold(events)
        } catch {
            throw StoreError.unreadableRow(table: "run_event", id: reading, reason: "\(task): \(error)")
        }
    }
}
