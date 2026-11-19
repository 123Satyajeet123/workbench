import Foundation

/// A new version of a machine tried on past days beside the current one. Its items live under its own trial task, so
/// the live machine never changes until the founder switches. Where the two agree, the current item's mark stands for
/// both; where they differ, the founder's marks decide. The verdict is an exact sign test, not a percentage: a few
/// marks make percentages noise.
public struct Trial: Sendable, Equatable {
    public enum Verdict: String, Sendable {
        case better, worse, notSure
    }

    /// Challenger items that repeat a current item.
    public var same: Int
    /// Challenger items with no current twin, and current items the challenger did not give.
    public var added: [Item]
    public var dropped: [Item]

    /// The trial task of a machine's challenger.
    public static func task(of task: String) -> String { "\(task)#trial" }
    public static func isTrial(_ task: String) -> Bool { task.hasSuffix("#trial") }
    public static func machineTask(of task: String) -> String { isTrial(task) ? String(task.dropLast(6)) : task }

    public init(current: [Item], challenger: [Item], citation: HelperSpec.Citation) {
        var twins = 0
        added = challenger.filter { new in
            let twin = current.contains { new.day == $0.day && new.repeats($0, citation: citation) }
            if twin { twins += 1 }
            return !twin
        }
        dropped = current.filter { old in
            !challenger.contains { old.day == $0.day && $0.repeats(old, citation: citation) }
        }
        same = twins
    }

    /// Where the versions differ and the founder's mark tells: dropping a wrong item or adding a right one is better;
    /// dropping a right one or adding a wrong one is worse.
    public var better: Int {
        dropped.filter { $0.state == .rejected }.count + added.filter { $0.state == .confirmed }.count
    }
    public var worse: Int {
        dropped.filter { $0.state == .confirmed }.count + added.filter { $0.state == .rejected }.count
    }
    /// Differences with no mark yet: the added items wait in Review; dropped items unmarked cannot tell.
    public var waiting: Int { added.filter { $0.state == .proposed }.count }

    /// Better or worse only when chance alone would give a split this one-sided at most 10% of the time.
    public var verdict: Verdict {
        let decided = better + worse
        guard decided > 0 else { return .notSure }
        if Binomial.atLeast(better, of: decided) <= 0.1 { return .better }
        if Binomial.atLeast(worse, of: decided) <= 0.1 { return .worse }
        return .notSure
    }
}

/// Exact binomial tails at p = 1/2.
enum Binomial {
    /// P(X ≥ k) for X ~ Binomial(n, 1/2).
    static func atLeast(_ k: Int, of n: Int) -> Double {
        guard k > 0 else { return 1 }
        guard k <= n else { return 0 }
        return (k...n).reduce(0) { sum, i in
            sum + exp(lgamma(Double(n + 1)) - lgamma(Double(i + 1)) - lgamma(Double(n - i + 1)) - Double(n) * log(2))
        }
    }
}
