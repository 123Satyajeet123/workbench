import Foundation

/// What the person can count on after a reading: the proposals kept and the proposals refused.
public struct RunYield: Sendable, Equatable {
    public var kept: Int
    public var dropped: Int

    public init(kept: Int, dropped: Int) {
        self.kept = kept
        self.dropped = dropped
    }
}

/// Why a list of events is not a journal.
public enum RunJournalError: Error, Equatable, CustomStringConvertible {
    case empty
    case noStart
    case startedTwice
    case partOutOfOrder(expected: Int, got: Int)
    case morePartsThanPlanned(planned: Int)
    case noPartYet
    case repeatedInPart
    case moreKeptAndDroppedThanProposed
    case afterFinish
    case afterStop
    case capCountedAsDrop
    case finishedEarly(read: Int, planned: Int)

    public var description: String {
        switch self {
        case .empty: "the journal has no events"
        case .noStart: "the first event is not started"
        case .startedTwice: "started comes twice"
        case .partOutOfOrder(let expected, let got): "part \(got) came where part \(expected) was due"
        case .morePartsThanPlanned(let planned): "a part comes after the \(planned) planned"
        case .noPartYet: "an event of a part comes before any part was read"
        case .repeatedInPart: "proposed, kept or dropped comes twice in one part"
        case .moreKeptAndDroppedThanProposed: "a part keeps and drops more than the model proposed"
        case .afterFinish: "an event comes after finished"
        case .afterStop: "an event other than finished comes after failed or cancelled"
        case .capCountedAsDrop: "a cap hit is counted in dropped"
        case .finishedEarly(let read, let planned):
            "finished after \(read) of \(planned) parts, with no failure or cancel"
        }
    }
}

/// A journal folded to what it says: the plan, the totals, and the last event. Only `fold` makes one, so a state is
/// always the state of a well formed journal.
public struct RunState: Sendable, Equatable {
    /// Why a reading ended before its last part.
    public enum Stop: Sendable, Equatable {
        case failed(Run.Failure)
        case cancelled
    }

    /// What one part has said so far.
    public struct Part: Sendable, Equatable {
        public var proposed: Int?
        public var kept: Int?
        public var dropped: Int?
    }

    public let lines: Int
    public let parts: Int
    public let promptHash: String
    public private(set) var partsRead = 0
    public private(set) var part = Part()
    public private(set) var proposed = 0
    public private(set) var kept = 0
    public private(set) var droppedByRule: [DropRule: Int] = [:]
    public private(set) var leftOut: [LeftOut.Part: Int] = [:]
    public private(set) var filed = 0
    public private(set) var asked = 0
    public private(set) var stop: Stop?
    public private(set) var cost: RunCost?
    /// The last event of the journal: the tail the now line reads.
    public private(set) var last: RunEvent

    public var isFinished: Bool { cost != nil }
    public var yield: RunYield { RunYield(kept: kept, dropped: droppedByRule.values.reduce(0, +)) }

    /// The state of `events`, or the first reason they are not a journal.
    public static func fold(_ events: [RunEvent]) throws(RunJournalError) -> RunState {
        guard let first = events.first else { throw .empty }
        guard case .started(let lines, let parts, let promptHash) = first else { throw .noStart }
        var state = RunState(lines: lines, parts: parts, promptHash: promptHash, last: first)
        for event in events.dropFirst() { try state.apply(event) }
        return state
    }

    private mutating func apply(_ event: RunEvent) throws(RunJournalError) {
        if isFinished { throw .afterFinish }
        if stop != nil {
            guard case .finished = event else { throw .afterStop }
        }
        switch event {
        case .started: throw .startedTwice
        case .partRead(let number, _, _): try openPart(number)
        case .proposed(let count):
            try say(\.proposed, count)
            proposed += count
        case .kept(let count):
            try say(\.kept, count)
            kept += count
        case .dropped(let reasons):
            if reasons[.leftOut] != nil { throw .capCountedAsDrop }
            try say(\.dropped, reasons.values.reduce(0, +))
            droppedByRule.merge(reasons, uniquingKeysWith: +)
        case .capHit(let cap, let count):
            try requirePart()
            leftOut[cap, default: 0] += count
        case .filed(let count):
            try requirePart()
            filed += count
        case .asked(let count):
            try requirePart()
            asked += count
        case .failed(let reason): stop = .failed(reason)
        case .cancelled: stop = .cancelled
        case .finished(let spent): try finish(with: spent)
        }
        last = event
    }

    private mutating func openPart(_ number: Int) throws(RunJournalError) {
        guard number == partsRead + 1 else { throw .partOutOfOrder(expected: partsRead + 1, got: number) }
        guard number <= parts else { throw .morePartsThanPlanned(planned: parts) }
        partsRead = number
        part = Part()
    }

    private func requirePart() throws(RunJournalError) {
        if partsRead == 0 { throw .noPartYet }
    }

    private mutating func say(_ field: WritableKeyPath<Part, Int?>, _ count: Int) throws(RunJournalError) {
        try requirePart()
        guard part[keyPath: field] == nil else { throw .repeatedInPart }
        part[keyPath: field] = count
        if (part.kept ?? 0) + (part.dropped ?? 0) > part.proposed ?? 0 { throw .moreKeptAndDroppedThanProposed }
    }

    private mutating func finish(with spent: RunCost) throws(RunJournalError) {
        if stop == nil, partsRead < parts { throw .finishedEarly(read: partsRead, planned: parts) }
        cost = spent
    }

    private init(lines: Int, parts: Int, promptHash: String, last: RunEvent) {
        self.lines = lines
        self.parts = parts
        self.promptHash = promptHash
        self.last = last
    }
}
