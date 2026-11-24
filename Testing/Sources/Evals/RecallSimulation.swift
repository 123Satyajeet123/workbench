import Foundation
import WorkbenchCore

/// P9: recall from a stratified draw of uncited lines (D6 §4.2). Each day, `cards` lines are drawn from each stratum
/// without replacement; the person says whether a drawn line holds a missed fact. The missed total is estimated by
/// Horvitz-Thompson (hits × stratum size / cards). Kept-right facts come from the precision audit: kept facts × the
/// share of audit answers that are right. R = kept right / (kept right + missed).
public struct RecallSimulation: Sendable {
    public struct LineStratum: Sendable {
        public var name: String
        public var share: Double
        public var missRate: Double
        public var cards: Int

        public init(_ name: String, share: Double, missRate: Double, cards: Int) {
            self.name = name
            self.share = share
            self.missRate = missRate
            self.cards = cards
        }
    }

    public var strata: [LineStratum]
    public var linesPerDay = 150
    public var days = 14
    public var factsPerDay = 16
    public var precision = 0.9
    public var auditChance = RunSettings.standard.pickChance
    public var trials = 2_000
    public var resamples = 400
    /// The chance that the ratio bound or a two-sided interval misses the truth.
    public var miss = 0.05
    public var seed: UInt64 = 20_261_124

    public init(strata: [LineStratum]) {
        self.strata = strata
    }

    public struct Result: Sendable {
        /// Mean estimated missed total over mean true missed total, minus 1.
        public var missedBias: Double
        /// The spread of (estimate − truth) over the mean true missed total.
        public var missedCV: Double
        public var meanTrueRecall: Double
        public var meanEstimatedRecall: Double
        /// Share of trials whose day-bootstrap 95% interval holds the true R.
        public var bootstrapCoverage: Double
        /// Share of trials whose ratio lower bound is at or below the true R.
        public var ratioBoundCoverage: Double
        public var medianRatioBound: Double
        public var medianBootstrapLow: Double
    }

    public func run() -> Result {
        var generator = SeededGenerator(seed: seed)
        var estimated: [Double] = []
        var truths: [Double] = []
        var recalls: [(truth: Double, estimate: Double, low: Double, high: Double, bound: Double)] = []
        for _ in 0..<trials {
            let window = (0..<days).map { _ in day(using: &generator) }
            let trueMissed = Double(window.map(\.trueMissed).reduce(0, +))
            let trueRight = Double(window.map(\.trueRight).reduce(0, +))
            let truth = trueRight / (trueRight + trueMissed)
            estimated.append(window.map(\.estimatedMissed).reduce(0, +))
            truths.append(trueMissed)
            let resampled = (0..<resamples).map { _ in
                Self.recall(of: (0..<days).map { _ in window[Int.random(in: 0..<days, using: &generator)] })
            }
            .sorted()
            recalls.append(
                (
                    truth, Self.recall(of: window), resampled[Int(Double(resamples) * miss / 2)],
                    resampled[Int(Double(resamples) * (1 - miss / 2)) - 1], ratioBound(window)
                ))
        }
        let meanTruth = truths.reduce(0, +) / Double(trials)
        let errors = zip(estimated, truths).map { $0 - $1 }
        let errorMean = errors.reduce(0, +) / Double(trials)
        let errorSpread = (errors.map { ($0 - errorMean) * ($0 - errorMean) }.reduce(0, +) / Double(trials))
            .squareRoot()
        let share = { (test: ((truth: Double, estimate: Double, low: Double, high: Double, bound: Double)) -> Bool) in
            Double(recalls.filter(test).count) / Double(trials)
        }
        return Result(
            missedBias: estimated.reduce(0, +) / Double(trials) / meanTruth - 1, missedCV: errorSpread / meanTruth,
            meanTrueRecall: recalls.map(\.truth).reduce(0, +) / Double(trials),
            meanEstimatedRecall: recalls.map(\.estimate).reduce(0, +) / Double(trials),
            bootstrapCoverage: share { $0.low <= $0.truth && $0.truth <= $0.high },
            ratioBoundCoverage: share { $0.bound <= $0.truth },
            medianRatioBound: recalls.map(\.bound).sorted()[trials / 2],
            medianBootstrapLow: recalls.map(\.low).sorted()[trials / 2])
    }

    struct Day {
        var trueMissed = 0
        var trueRight = 0
        var kept = 0
        var answers = 0
        var wrongAnswers = 0
        var estimatedMissed = 0.0
        var lines: [Int] = []
        var hits: [Int] = []
        var drawn: [Int] = []
    }

    private func day(using generator: inout SeededGenerator) -> Day {
        var day = Day(kept: factsPerDay)
        for _ in 0..<factsPerDay {
            let right = Double.random(in: 0..<1, using: &generator) < precision
            if right { day.trueRight += 1 }
            if Double.random(in: 0..<1, using: &generator) < auditChance {
                day.answers += 1
                if !right { day.wrongAnswers += 1 }
            }
        }
        var sizes = Array(repeating: 0, count: strata.count)
        for _ in 0..<linesPerDay { sizes[generator.index(byShare: strata.map(\.share))] += 1 }
        for (stratum, size) in zip(strata, sizes) {
            let missed = (0..<size).filter { _ in Double.random(in: 0..<1, using: &generator) < stratum.missRate }.count
            let drawn = min(stratum.cards, size)
            var (left, leftMissed, hits) = (size, missed, 0)
            for _ in 0..<drawn {
                if Int.random(in: 0..<left, using: &generator) < leftMissed {
                    hits += 1
                    leftMissed -= 1
                }
                left -= 1
            }
            day.trueMissed += missed
            if drawn > 0 { day.estimatedMissed += Double(hits * size) / Double(drawn) }
            day.lines.append(size)
            day.hits.append(hits)
            day.drawn.append(drawn)
        }
        return day
    }

    private static func recall(of window: [Day]) -> Double {
        let answers = window.map(\.answers).reduce(0, +)
        let precision = answers == 0 ? 1 : 1 - Double(window.map(\.wrongAnswers).reduce(0, +)) / Double(answers)
        let right = Double(window.map(\.kept).reduce(0, +)) * precision
        let missed = window.map(\.estimatedMissed).reduce(0, +)
        return right + missed == 0 ? 1 : right / (right + missed)
    }

    /// Kept right at its lower bound over kept right plus missed at its upper bound. Each stratum's miss rate and the
    /// precision get an exact binomial bound at confidence 1 − miss / (strata + 1), so all hold together.
    private func ratioBound(_ window: [Day]) -> Double {
        let confidence = 1 - miss / Double(strata.count + 1)
        let wrong = ClopperPearson.upperBound(
            wrong: window.map(\.wrongAnswers).reduce(0, +), of: window.map(\.answers).reduce(0, +),
            confidence: confidence)
        let rightLow = Double(window.map(\.kept).reduce(0, +)) * (1 - wrong)
        let missedHigh = strata.indices.map { index in
            ClopperPearson.upperBound(
                wrong: window.map { $0.hits[index] }.reduce(0, +), of: window.map { $0.drawn[index] }.reduce(0, +),
                confidence: confidence) * Double(window.map { $0.lines[index] }.reduce(0, +))
        }
        .reduce(0, +)
        return rightLow / (rightLow + missedHigh)
    }
}
