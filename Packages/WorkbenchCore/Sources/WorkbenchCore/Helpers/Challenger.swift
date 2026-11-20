import Foundation

/// A new version of a machine tried on past days beside the current one. Its items live under its own trial task, so
/// the live machine never changes until the founder switches. Where the two agree, the current item's mark stands for
/// both; where they differ, the founder's marks decide, one at a time, through an always-valid test (research 20 §3).
public struct Trial: Sendable, Equatable {
    public enum Verdict: String, Sendable {
        case better, worse, notSure
    }

    /// Challenger items that repeat a current item.
    public var same: Int
    /// Challenger items with no current twin, and current items the challenger did not give.
    public var added: [Item]
    public var dropped: [Item]
    /// Each marked difference in the order its mark was given: true where the challenger is right.
    public var outcomes: [Bool]
    /// The e-value either direction must reach.
    public var threshold: Double

    /// The trial task of a machine's challenger.
    public static func task(of task: String) -> String { "\(task)#trial" }
    public static func isTrial(_ task: String) -> Bool { task.hasSuffix("#trial") }
    public static func machineTask(of task: String) -> String { isTrial(task) ? String(task.dropLast(6)) : task }

    /// `markOrder` gives each marked item's latest mark id, so the test sees the marks in the order they came.
    public init(
        current: [Item], challenger: [Item], citation: HelperSpec.Citation, choices: [String] = [],
        markOrder: [Int64: Int64] = [:],
        threshold: Double = EProcess.threshold(challengers: 1)
    ) {
        var twins = 0
        added = challenger.filter { new in
            let twin = current.contains { new.day == $0.day && new.repeats($0, citation: citation, choices: choices) }
            if twin { twins += 1 }
            return !twin
        }
        dropped = current.filter { old in
            !challenger.contains { old.day == $0.day && $0.repeats(old, citation: citation, choices: choices) }
        }
        same = twins
        self.threshold = threshold
        // Dropping a wrong item or adding a right one is better; dropping a right one or adding a wrong one is worse.
        let units: [(order: Int64, better: Bool)] =
            dropped.compactMap { item in
                item.state == .proposed ? nil : (markOrder[item.id ?? 0] ?? 0, item.state == .rejected)
            }
            + added.compactMap { item in
                item.state == .proposed ? nil : (markOrder[item.id ?? 0] ?? 0, item.state == .confirmed)
            }
        outcomes = units.sorted { $0.order < $1.order }.map(\.better)
    }

    public var better: Int { outcomes.filter { $0 }.count }
    public var worse: Int { outcomes.filter { !$0 }.count }
    /// Differences with no mark yet: the added items wait in Review; dropped items unmarked cannot tell.
    public var waiting: Int { added.filter { $0.state == .proposed }.count }

    public var verdict: Verdict { EProcess.verdict(outcomes, threshold: threshold) }
}

/// Always-valid tests by betting (Ramdas et al., arXiv 2210.01948): the e-value may be read after every mark, and the
/// chance it ever reaches 1/α when nothing is there is at most α (Ville's inequality). Each process is the average
/// over a grid of bet sizes, which is itself an e-process. One tool serves promotion and rollback (research 20 §3.2).
public enum EProcess {
    /// The share of false verdicts the whole test may give.
    public static let level = 0.10
    static let grid = (1...9).map { Double($0) / 10 }

    /// Both directions, and every challenger tried in the window, share the level (Bonferroni on e-values).
    public static func threshold(challengers: Int) -> Double { 2 * Double(max(challengers, 1)) / level }

    /// Better when the bet on "the challenger wins differences" reaches the threshold first; worse when the bet on
    /// "it loses them" does. Measured on synthetic data (A = 20, 4,000 runs): with no real difference 3.9% false
    /// better and 3.7% false worse; at a 70% win share, better every time after a median of 34 marked differences.
    public static func verdict(_ outcomes: [Bool], threshold: Double) -> Trial.Verdict {
        var up = Array(repeating: 1.0, count: grid.count)
        var down = up
        for won in outcomes {
            let sign = won ? 1.0 : -1.0
            for (index, bet) in grid.enumerated() {
                up[index] *= 1 + bet * sign
                down[index] *= 1 - bet * sign
            }
            if mean(up) >= threshold { return .better }
            if mean(down) >= threshold { return .worse }
        }
        return .notSure
    }

    /// The highest e-value against "wrong at most `target` of the time" over answers in order (true = wrong). An
    /// alarm fires when it reaches 1/α.
    public static func alarm(_ wrong: [Bool], target: Double = 0.1) -> Double {
        let bets = grid.map { $0 / target }
        var wealth = Array(repeating: 1.0, count: bets.count)
        var highest = 1.0
        for answer in wrong {
            let x = answer ? 1.0 : 0.0
            for (index, bet) in bets.enumerated() { wealth[index] *= 1 + bet * (x - target) }
            highest = max(highest, mean(wealth))
        }
        return highest
    }

    private static func mean(_ values: [Double]) -> Double { values.reduce(0, +) / Double(values.count) }
}
