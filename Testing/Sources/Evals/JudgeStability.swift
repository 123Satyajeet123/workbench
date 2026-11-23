import Foundation
import WorkbenchCore

/// The calls a rubric judge made for one rubric item of one note: per run, the verdict in the given order and in the
/// reversed order. Without any label these show how steady the judge is.
public struct ItemObservation: Sendable, Equatable {
    public var note: String
    public var item: String
    /// `[run][order]`, the order 0 as given and 1 reversed.
    public var verdicts: [[Verdict]]

    public init(note: String, item: String, verdicts: [[Verdict]]) {
        self.note = note
        self.item = item
        self.verdicts = verdicts
    }

    /// The verdict the judge gives: the orders must agree in a run, and the majority of runs decides.
    public var resolved: Verdict { RubricTally.resolve(verdicts).verdict }
}

/// A count out of a total, with the exact one-sided 95% upper bound of the rate it estimates.
public struct Rate: Sendable, Equatable, CustomStringConvertible {
    public var count: Int
    public var total: Int

    public init(_ count: Int, of total: Int) {
        self.count = count
        self.total = total
    }

    public var value: Double? { total == 0 ? nil : Double(count) / Double(total) }

    public var description: String {
        guard let value else { return "n/a (0 calls)" }
        let upper = ClopperPearson.upperBound(wrong: count, of: total, confidence: 0.95)
        return String(format: "%.1f%% (%d of %d, 95%% upper bound %.1f%%)", 100 * value, count, total, 100 * upper)
    }
}

public enum JudgeStability {
    /// Calls where the two orders gave the same verdict.
    public static func orderConsistency(_ observations: [ItemObservation]) -> Rate {
        let runs = observations.flatMap(\.verdicts)
        return Rate(runs.filter { Set($0).count == 1 }.count, of: runs.count)
    }

    /// Single calls (the given order) that differ from the verdict of the majority of the three runs.
    public static func singleCallFlip(_ observations: [ItemObservation]) -> Rate {
        let singles = observations.flatMap { observation in observation.verdicts.map { ($0[0], observation.resolved) } }
        return Rate(singles.filter { $0.0 != $0.1 }.count, of: singles.count)
    }

    /// Items where the three runs in the given order did not all agree.
    public static func retestDisagreement(_ observations: [ItemObservation]) -> Rate {
        Rate(observations.filter { Set($0.verdicts.map { $0[0] }).count > 1 }.count, of: observations.count)
    }

    /// Items whose resolved verdict is unknown only because the orders or the runs disagreed.
    public static func tied(_ observations: [ItemObservation]) -> Rate {
        Rate(
            observations.filter { $0.resolved == .unknown && $0.verdicts.contains { Set($0).count > 1 } }.count,
            of: observations.count)
    }

    /// How many items changed their resolved verdict between a base run and a variant of the same note, and how many
    /// of those moved toward pass.
    public static func change(from base: [ItemObservation], to variant: [ItemObservation]) -> (
        changed: Rate, towardPass: Rate
    ) {
        let pairs = base.compactMap { item in
            variant.first { $0.note == item.note && $0.item == item.item }.map { (item.resolved, $0.resolved) }
        }
        return (
            Rate(pairs.filter { $0.0 != $0.1 }.count, of: pairs.count),
            Rate(pairs.filter { $0.0 != .pass && $0.1 == .pass }.count, of: pairs.count)
        )
    }

    /// The share of items resolved as pass.
    public static func passRate(_ observations: [ItemObservation]) -> Rate {
        Rate(observations.filter { $0.resolved == .pass }.count, of: observations.count)
    }
}
