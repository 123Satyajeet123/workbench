import Foundation

public struct Trial: Sendable, Equatable {
    public enum Verdict: String, Sendable {
        case better, worse, notSure
    }

    public var same: Int
    public var added: [Item]
    public var dropped: [Item]
    public var outcomes: [Bool]
    public var threshold: Double

    public static func task(of task: String) -> String { "\(task)#trial" }
    public static func isTrial(_ task: String) -> Bool { task.hasSuffix("#trial") }
    public static func machineTask(of task: String) -> String { isTrial(task) ? String(task.dropLast(6)) : task }

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
    public var waiting: Int { added.filter { $0.state == .proposed }.count }

    public var verdict: Verdict { EProcess.verdict(outcomes, threshold: threshold) }
}

public enum EProcess {
    public static let level = 0.10
    static let grid = (1...9).map { Double($0) / 10 }

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
