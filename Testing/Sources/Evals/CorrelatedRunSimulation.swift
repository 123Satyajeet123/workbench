import Foundation
import WorkbenchCore

/// Runs of random size whose items are wrong together: each run has its own wrong rate, drawn from a Beta law with
/// mean `wrongMean`. A small `concentration` makes the items of a run alike; a large one makes them independent.
public struct CorrelatedRuns {
    public static let sizes = [1, 2, 5, 10, 20, 40]

    public var concentration: Double
    private var generator: SeededGenerator
    private var runCount: Int64 = 0

    public init(concentration: Double, seed: UInt64) {
        self.concentration = concentration
        generator = SeededGenerator(seed: seed)
    }

    /// The audited answers of one new run, each of its items picked with `chance`. Empty when none is picked.
    /// `keepRun` false leaves the run id off, so each answer stands alone.
    public mutating func auditedAnswers(wrongMean: Double, chance: Double, keepRun: Bool) -> [Certificate.Answer] {
        runCount += 1
        let size = Self.sizes[Int.random(in: 0..<Self.sizes.count, using: &generator)]
        let wrongRate = beta(mean: wrongMean)
        return (0..<size).compactMap { _ in
            guard Double.random(in: 0..<1, using: &generator) < chance else { return nil }
            return Certificate.Answer(
                wrong: Double.random(in: 0..<1, using: &generator) < wrongRate, chance: chance,
                run: keepRun ? runCount : nil)
        }
    }

    private mutating func beta(mean: Double) -> Double {
        let low = gamma(shape: mean * concentration)
        let high = gamma(shape: (1 - mean) * concentration)
        return low / (low + high)
    }

    /// Marsaglia and Tsang; a shape below 1 is raised by one and scaled back.
    private mutating func gamma(shape: Double) -> Double {
        guard shape >= 1 else {
            return gamma(shape: shape + 1) * pow(Double.random(in: 0..<1, using: &generator), 1 / shape)
        }
        let d = shape - 1.0 / 3
        let c = 1 / (3 * d).squareRoot()
        while true {
            let x = normal()
            let v = pow(1 + c * x, 3)
            guard v > 0 else { continue }
            let u = Double.random(in: 0..<1, using: &generator)
            if log(u) < 0.5 * x * x + d - d * v + d * log(v) { return d * v }
        }
    }

    private mutating func normal() -> Double {
        let u = 1 - Double.random(in: 0..<1, using: &generator)
        let v = Double.random(in: 0..<1, using: &generator)
        return (-2 * log(u)).squareRoot() * cos(2 * .pi * v)
    }
}

/// How many wealth steps one audit stream takes to reach "earned": a step per audited item, or a step per run.
public enum StepRule: String, Sendable, CaseIterable {
    case perItem = "one step per audited item (before)"
    case perRun = "one step per run (now)"
}

/// How often a certificate earns when the helper's wrong rate is exactly `Certificate.allowedWrong`, so every
/// "earned" is false, with items of a run alike.
public struct CorrelatedRunSimulation: Sendable {
    public var trials = 4_000
    public var horizonSteps = 400
    public var seed: UInt64 = 20_261_123

    public init() {}

    /// The share of trials that earned within `horizonSteps` steps, read after every step.
    public func falseEarned(_ rule: StepRule, concentration: Double) -> Double {
        var runs = CorrelatedRuns(concentration: concentration, seed: seed)
        var earned = 0
        for _ in 0..<trials where earns(rule, from: &runs) { earned += 1 }
        return Double(earned) / Double(trials)
    }

    private func earns(_ rule: StepRule, from runs: inout CorrelatedRuns) -> Bool {
        var wealth = Certificate.Wealth()
        var steps = 0
        while steps < horizonSteps {
            let answers = runs.auditedAnswers(
                wrongMean: Certificate.allowedWrong, chance: AuditPolicy.pickChance, keepRun: rule == .perRun)
            let stepsFromRun = rule == .perRun ? [answers] : answers.map { [$0] }
            for step in stepsFromRun where !step.isEmpty {
                wealth.add(run: step)
                steps += 1
                if wealth.value >= Certificate.threshold { return true }
            }
        }
        return false
    }
}
