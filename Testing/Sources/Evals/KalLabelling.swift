import Foundation
import WorkbenchCore

/// Days the founder keeps out of every dev tool: nothing may show or label a line sent on one of them.
public struct HeldOutDays: Sendable, Equatable {
    public var days: ClosedRange<WorkDay>

    public init(from first: WorkDay, through last: WorkDay) { days = first...last }

    /// 23 November to 6 December 2026.
    public static let founder = HeldOutDays(from: WorkDay("2026-11-23")!, through: WorkDay("2026-12-06")!)

    public struct Refused: Error, Equatable {
        public var day: String
    }

    /// Whether a day may be shown: outside the range, and in the dev set of the repo's hash split (`EvalSplit`).
    public func keeps(_ day: WorkDay) -> Bool { !days.contains(day) && EvalSplit(day) == .dev }

    /// Throws for the first of `requested` that is in the range.
    public func require(noneOf requested: [WorkDay]) throws {
        if let held = requested.first(where: { days.contains($0) }) { throw Refused(day: held.description) }
    }
}

public enum KalLabel: String, Codable, Sendable {
    case past, future
}

/// One line that holds one of the words, as the founder is shown it.
public struct LabelLine: Sendable, Equatable {
    public var day: WorkDay
    /// The stable id of the line, so the label joins to it later without copying its words.
    public var id: String
    public var text: String

    public init(day: WorkDay, id: String, text: String) {
        self.day = day
        self.id = id
        self.text = text
    }
}

public protocol LabelLineSource {
    func lines(on day: WorkDay) throws -> [LabelLine]
}

/// A label as written to the file: the day and the line id, never the words.
public struct LabelRecord: Codable, Sendable, Equatable {
    public var day: String
    public var line: String
    public var label: KalLabel
}

public enum LabelAnswer: Sendable, Equatable {
    case label(KalLabel)
    case skip
    case quit
}

/// Probe P-F4: the founder says, for each line with a "kal" or "parson" word of a dev week, whether the word means
/// the past or the future. The words are data given by the caller; this type reads none of its own.
public struct KalLabelling {
    public static let daysInWeek = 7

    public let source: any LabelLineSource
    public let terms: Set<String>
    public let heldOut: HeldOutDays

    public init(source: any LabelLineSource, terms: [String], heldOut: HeldOutDays = .founder) {
        self.source = source
        self.terms = Set(terms.map(\.comparable))
        self.heldOut = heldOut
    }

    /// The lines of the seven days from `first` that hold a term, in day order. The whole week is refused when any of
    /// its days is in the range. A day that the hash split holds out is left out, and none of its lines is shown.
    public func candidates(weekStarting first: WorkDay) throws -> [LabelLine] {
        let week = (0..<Self.daysInWeek).map { first.adding(days: $0) }
        try heldOut.require(noneOf: week)
        let shown = week.filter(heldOut.keeps)
        return try shown.flatMap { try source.lines(on: $0) }.filter { heldOut.keeps($0.day) }.filter(holdsATerm)
    }

    private func holdsATerm(_ line: LabelLine) -> Bool {
        line.text.comparable.split { !$0.isLetter }.contains { terms.contains(String($0)) }
    }

    /// Shows each candidate once, in order, and records each label as it is given. Returns how many were labelled.
    @discardableResult
    public func run(
        weekStarting first: WorkDay, ask: (LabelLine, _ number: Int, _ of: Int) -> LabelAnswer,
        record: (LabelRecord) throws -> Void
    ) throws -> Int {
        let lines = try candidates(weekStarting: first)
        var labelled = 0
        for (index, line) in lines.enumerated() {
            switch ask(line, index + 1, lines.count) {
            case .label(let label):
                try record(LabelRecord(day: line.day.description, line: line.id, label: label))
                labelled += 1
            case .skip: continue
            case .quit: return labelled
            }
        }
        return labelled
    }
}

extension LabelRecord {
    /// One line of JSON, for a file the founder appends to.
    public var jsonLine: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: (try? encoder.encode(self)) ?? Data(), as: UTF8.self)
    }
}
