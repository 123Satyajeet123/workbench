import Foundation

/// The numbers of the tasks of one group for one model, from its records.
public struct PageEvalGroupSummary: Codable, Sendable, Equatable {
    public var group: String
    public var tasks: [String]
    /// The tasks of the group that test a rule that is not built yet. They are not in `passedPerRun`.
    public var expectedFailures: [String]
    /// For each run, how many of the other tasks of the group passed.
    public var passedPerRun: [Int]
    public var refusalsByReason: [String: Int]
    public var costUSD: Double
    public var medianRunRowSeconds: Double
    public var medianWallSeconds: Double
    public var costPerRequestUSD: Double
    public var medianTurns: Double
    /// Calls of each tool over the group, from the tool server's log.
    public var toolCalls: [String: Int]

    init(group: String, tasks: [PageEvalTask], runs: Int, records: [PageEvalRecord]) {
        self.group = group
        self.tasks = tasks.map(\.name)
        let expected = tasks.filter(\.isExpectedFailure).map(\.name)
        expectedFailures = expected
        let mine = records.filter { $0.group == group }
        passedPerRun = (1...runs).map { run in
            mine.filter { $0.run == run && $0.passed && !expected.contains($0.task) }.count
        }
        refusalsByReason = PageEvalModelSummary.refusals(of: mine)
        costUSD = mine.map(\.costUSD).reduce(0, +)
        medianRunRowSeconds = PageEvalModelSummary.median(mine.map(\.runRowSeconds))
        medianWallSeconds = PageEvalModelSummary.median(mine.map(\.wallSeconds))
        costPerRequestUSD = mine.isEmpty ? 0 : costUSD / Double(mine.count)
        medianTurns = PageEvalModelSummary.median(mine.map { Double($0.turns) })
        toolCalls = PageEvalModelSummary.toolCalls(of: mine)
    }

    var scoredCount: Int { tasks.count - expectedFailures.count }

    var text: String {
        let passed = passedPerRun.map(String.init).joined(separator: ", ")
        let scored = scoredCount == 0 ? "no scored task" : "passed per run: \(passed) of \(scoredCount)"
        let expected =
            expectedFailures.isEmpty ? "" : "; expected to fail: \(expectedFailures.joined(separator: ", "))"
        return String(
            format: "%@: %@%@; cost %.2f USD (%.3f per request); median %.1f s (wall clock), %.1f turns; tool calls %@",
            group, scored, expected, costUSD, costPerRequestUSD, medianWallSeconds, medianTurns,
            PageEvalModelSummary.toolCallsText(toolCalls))
    }
}

/// The numbers of one model, from its records. Pure: the same records give the same summary. The pass rates count
/// the tasks that are not expected to fail.
public struct PageEvalModelSummary: Codable, Sendable, Equatable {
    public var model: String
    public var arm: PageEvalArm
    public var tasks: [String]
    /// The tasks that test a rule that is not built yet; a pass of one of them is not counted.
    public var expectedFailures: [String]
    /// For each task, whether each run passed.
    public var passes: [[Bool]]
    public var passedPerRun: [Int]
    public var passRatePerRun: [Double]
    public var passRate: Double
    public var flippingTasks: [String]
    public var groups: [PageEvalGroupSummary]
    public var refusalsByReason: [String: Int]
    public var attemptsWithoutProposal: Int
    public var costUSD: Double
    public var costPerRunUSD: [Double]
    public var medianRunRowSeconds: Double
    public var medianWallSeconds: Double

    init(model: String, arm: PageEvalArm, tasks all: [PageEvalTask], runs: Int, records every: [PageEvalRecord]) {
        self.model = model
        self.arm = arm
        let names = all.map(\.name)
        let expected = all.filter(\.isExpectedFailure).map(\.name)
        tasks = names
        expectedFailures = expected
        let records = every.filter { $0.model == model && $0.arm == arm.rawValue }
        let grid = names.map { name in
            (1...runs).map { run in records.contains { $0.task == name && $0.run == run && $0.passed } }
        }
        passes = grid
        let scored = zip(names, grid).filter { !expected.contains($0.0) }.map(\.1)
        let passed = (0..<runs).map { run in scored.filter { $0[run] }.count }
        passedPerRun = passed
        passRatePerRun = passed.map { Double($0) / Double(scored.count) }
        passRate = Double(passed.reduce(0, +)) / Double(scored.count * runs)
        flippingTasks = zip(names, grid).filter { Set($0.1).count > 1 }.map(\.0)
        groups = all.reduce(into: [String]()) { if !$0.contains($1.group) { $0.append($1.group) } }.map { group in
            PageEvalGroupSummary(
                group: group, tasks: all.filter { $0.group == group }, runs: runs,
                records: records.filter { $0.group == group })
        }
        refusalsByReason = Self.refusals(of: records)
        attemptsWithoutProposal = records.filter { $0.callFailure != nil }.count
        costUSD = records.map(\.costUSD).reduce(0, +)
        costPerRunUSD = (1...runs).map { run in records.filter { $0.run == run }.map(\.costUSD).reduce(0, +) }
        medianRunRowSeconds = Self.median(records.map(\.runRowSeconds))
        medianWallSeconds = Self.median(records.map(\.wallSeconds))
    }

    static func refusals(of records: [PageEvalRecord]) -> [String: Int] {
        records.flatMap(\.verdicts).compactMap(\.refusal).reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    static func toolCalls(of records: [PageEvalRecord]) -> [String: Int] {
        records.flatMap(\.toolCalls).reduce(into: [:]) { $0[$1.key, default: 0] += $1.value }
    }

    static func toolCallsText(_ calls: [String: Int]) -> String {
        calls.isEmpty
            ? "none" : calls.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// The table of the model: a row for each task with a mark for each run, then the summary lines.
    public var text: String {
        let width = tasks.map(\.count).max() ?? 0
        let rows = zip(tasks, passes).map { name, runs in
            let expected = expectedFailures.contains(name)
            return name.padding(toLength: width, withPad: " ", startingAt: 0) + "  "
                + runs.map { $0 ? (expected ? "UNEXPECTED PASS" : "pass") : (expected ? "xfail" : "FAIL") }
                .joined(separator: "  ") + (flippingTasks.contains(name) ? "  (flips)" : "")
        }
        let refusals = refusalsByReason.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(
            separator: ", ")
        return
            ([
                "\(model), arm \(arm.rawValue)  (dev, synthetic)",
                "task".padding(toLength: width, withPad: " ", startingAt: 0) + "  "
                    + (1...passes[0].count).map { "run\($0)" }.joined(separator: "  "),
            ] + rows + [
                "passed per run: \(passedPerRun.map(String.init).joined(separator: ", ")) of \(tasks.count - expectedFailures.count)"
                    + " (\(passRatePerRun.map { String(format: "%.0f%%", 100 * $0) }.joined(separator: ", ")))"
                    + ", not counting the tasks expected to fail",
                String(format: "overall pass rate: %.1f%%", 100 * passRate),
                "tasks that flip between runs: \(flippingTasks.isEmpty ? "none" : flippingTasks.joined(separator: ", "))",
                "refusals by reason: \(refusals.isEmpty ? "none" : refusals)",
                "attempts with no proposal: \(attemptsWithoutProposal)",
                String(
                    format:
                        "cost: %.2f USD (per run: %@), median %.1f s per request (run rows, whole seconds), %.1f s (wall clock)",
                    costUSD, costPerRunUSD.map { String(format: "%.2f", $0) }.joined(separator: ", "),
                    medianRunRowSeconds, medianWallSeconds),
                "groups:",
            ] + groups.map { "  " + $0.text }).joined(separator: "\n")
    }
}

/// Everything the eval writes to its file.
public struct PageEvalResult: Codable, Sendable {
    public var date: Date
    public var note: String
    public var models: [String]
    public var arms: [PageEvalArm]
    public var runs: Int
    public var factCount: Int
    public var records: [PageEvalRecord]
    /// The instructions of each arm, by arm name, as the model got them.
    public var instructions: [String: String]
    public var summaries: [PageEvalModelSummary]
}
