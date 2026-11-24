import Foundation

/// Whether a helper has earned trust, from its audit answers on held-out days in the order they were given. The
/// answers of one run move the bettor once: a bettor bets, run after run, that the helper's wrong rate is above
/// `allowedWrong`. Items of one run are alike, so a step per answer would count one run many times; a step per run
/// keeps each step's mean at or below zero when the wrong rate is `allowedWrong` or higher.
///
/// A run's step is the mean over its answers of `share · (allowedWrong − wrong)`. A right answer makes the bettor
/// richer (the factor `1 + g / (1 − allowedWrong) · step` is above 1 for a positive step) and a wrong one poorer, so
/// the wealth is an e-value against "wrong at most allowedWrong is false" (Waudby-Smith and Ramdas, arXiv
/// 2010.09686). "Earned" means the wealth is at least 1 / (1 − `confidence`). When the true wrong rate is
/// `allowedWrong` or higher, the chance that the wealth ever reaches that bar is at most 1 − `confidence` (Ville's
/// inequality), however often the certificate is read.
///
/// A second bettor, `DriftAlarm`, bets that the wrong rate is above `allowedWrong` on the same steps. When it reaches
/// its bar, the wealth starts again from 1 and only later runs count: "earned" is lost until it is earned again.
///
/// An answer weighs one over the chance its item had of being picked, over the heaviest weight. A pick chance below
/// `RunSettings.pickChance` is refused: the answer is left out, not clamped.
public struct Certificate: Sendable, Equatable {
    public enum Status: Sendable, Equatable, Codable {
        /// At least this many more runs, each with all its audited answers right and at the heaviest weight, before
        /// it is earned.
        case needsMore(Int)
        /// The wrong rate is at most this, with `confidence`, however often the answers were read.
        case earned(bound: Double)
    }

    public struct Answer: Sendable, Equatable {
        public var wrong: Bool
        /// The chance the answered item had of being the one picked, above 0 and at most 1.
        public var chance: Double
        /// The run that made the item. An answer with no run is a run of its own.
        public var run: Int64?

        public init(wrong: Bool, chance: Double, run: Int64? = nil) {
            self.wrong = wrong
            self.chance = chance
            self.run = run
        }

        /// Whether the chance is at least `pickChance`, the smallest the weights allow.
        func isCounted(pickChance: Double) -> Bool { chance >= pickChance }

        /// The weight over the heaviest weight: above 0 and at most 1 for a counted answer.
        func share(pickChance: Double) -> Double { 1 / chance / (1 / pickChance) }
    }

    /// The step of one run against "wrong at most `rate`": the mean over its counted answers of
    /// `share · (rate − wrong)`, or nil when none is counted. It lies between `rate − 1` and `rate`.
    static func step(of run: [Answer], against rate: Double, pickChance: Double) -> Double? {
        let counted = run.filter { $0.isCounted(pickChance: pickChance) }
        guard !counted.isEmpty else { return nil }
        return counted.map { $0.share(pickChance: pickChance) * (rate - ($0.wrong ? 1 : 0)) }.reduce(0, +)
            / Double(counted.count)
    }

    /// The wealth of a bettor against "wrong at most `rate`", averaged over a grid of bet sizes (a mean of
    /// e-processes is an e-process). A bet is a share `g` of the most the bettor may risk, 1 / (1 − rate) per unit of
    /// step, so the wealth stays above zero for any step.
    public struct Wealth: Sendable, Equatable {
        private let rate: Double
        private let pickChance: Double
        private var perBet = Array(repeating: 1.0, count: EProcess.grid.count)

        public init(
            against rate: Double = RunSettings.standard.allowedWrong,
            pickChance: Double = RunSettings.standard.pickChance
        ) {
            self.rate = rate
            self.pickChance = pickChance
        }

        /// One step for all the answers of one run.
        public mutating func add(run: [Answer]) {
            guard let step = Certificate.step(of: run, against: rate, pickChance: pickChance) else { return }
            for (index, bet) in EProcess.grid.enumerated() { perBet[index] *= 1 + bet / (1 - rate) * step }
        }

        /// A run of one answer.
        public mutating func add(_ answer: Answer) { add(run: [answer]) }

        public var value: Double { perBet.reduce(0, +) / Double(perBet.count) }
    }

    /// The wealth at which a certificate of this confidence is earned.
    public static func threshold(at confidence: Double) -> Double { 1 / (1 - confidence) }

    public var answers: [Answer]
    public var settings: RunSettings

    public init(answers: [Answer] = [], settings: RunSettings = .standard) {
        self.answers = answers
        self.settings = settings
    }

    /// Earned once the wealth reaches its bar after the drift alarm last fired. Ville's inequality bounds the chance
    /// that the wealth ever reaches the bar under the null, so a later dip does not take trust away; only the drift
    /// alarm does.
    public var status: Status { status(at: settings.confidence) }

    /// The status at another confidence: a rung that asks for more than 0.9 reads it here.
    public func status(at confidence: Double) -> Status {
        let runs = replay.runsSinceAlarm
        let threshold = Self.threshold(at: confidence)
        var wealth = Wealth(against: settings.allowedWrong, pickChance: settings.pickChance)
        for run in runs {
            wealth.add(run: run)
            if wealth.value >= threshold { return .earned(bound: upperBound(of: runs, threshold: threshold)) }
        }
        return .needsMore(rightRunsToEarn(from: wealth, threshold: threshold))
    }

    /// The evidence the drift alarm had when it first reached its bar, or nil if it never did.
    public var firstAlarm: Double? { replay.firstAlarm }

    /// The answers of each run, runs in the order their last answer came. A run waits for its last answer, so no run
    /// counts in part.
    private var runs: [[Answer]] {
        var lastIndex: [Int64: Int] = [:]
        for (index, answer) in answers.enumerated() { answer.run.map { lastIndex[$0] = index } }
        var waiting: [Int64: [Answer]] = [:]
        var runs: [[Answer]] = []
        for (index, answer) in answers.enumerated() {
            guard let run = answer.run else {
                runs.append([answer])
                continue
            }
            waiting[run, default: []].append(answer)
            if lastIndex[run] == index, let complete = waiting.removeValue(forKey: run) { runs.append(complete) }
        }
        return runs
    }

    /// The runs since the drift alarm last reached its bar, and the evidence at its first alarm.
    private var replay: (runsSinceAlarm: [[Answer]], firstAlarm: Double?) {
        var alarm = driftAlarm
        var runsSinceAlarm: [[Answer]] = []
        var firstAlarm: Double?
        for run in runs {
            runsSinceAlarm.append(run)
            alarm.add(run: run)
            if alarm.isRaised {
                firstAlarm = firstAlarm ?? alarm.value
                runsSinceAlarm = []
                alarm = driftAlarm
            }
        }
        return (runsSinceAlarm, firstAlarm)
    }

    private var driftAlarm: DriftAlarm {
        DriftAlarm(against: settings.allowedWrong, delta: settings.delta, pickChance: settings.pickChance)
    }

    private func wealth(of runs: [[Answer]], against rate: Double) -> Wealth {
        runs.reduce(into: Wealth(against: rate, pickChance: settings.pickChance)) { $0.add(run: $1) }
    }

    private func rightRunsToEarn(from start: Wealth, threshold: Double) -> Int {
        var wealth = start
        var more = 0
        while wealth.value < threshold {
            wealth.add(Answer(wrong: false, chance: settings.pickChance))
            more += 1
        }
        return more
    }

    /// The least wrong rate the bettor can still bet against with enough wealth to count: the upper end of the
    /// confidence sequence. The wealth only grows with the rate, so a bisection finds it below `allowedWrong`.
    private func upperBound(of runs: [[Answer]], threshold: Double) -> Double {
        var (low, high) = (0.0, settings.allowedWrong)
        for _ in 0..<40 {
            let middle = (low + high) / 2
            if wealth(of: runs, against: middle).value >= threshold { high = middle } else { low = middle }
        }
        return high
    }
}

/// An e-CUSUM against "wrong at least `rate`" is false: it bets, run after run, that the wrong rate is above `rate`
/// (Shin, Ramdas and Rinaldo, arXiv 2203.03532; research 13 section 6.5). It takes the run steps of `Certificate`
/// with the sign turned: under "wrong at most `rate`" each factor has mean at most 1. Each bet restarts from 1 when
/// its wealth falls below 1, so a long good stretch does not hide a later jump. It is raised when the mean wealth
/// reaches 1 / `delta`; under "wrong at most `rate`" the runs to a false alarm are at least 1 / `delta` on average.
public struct DriftAlarm: Sendable, Equatable {
    private let rate: Double
    private let level: Double
    private let pickChance: Double
    private var perBet = Array(repeating: 1.0, count: EProcess.grid.count)

    public init(
        against rate: Double = RunSettings.standard.allowedWrong, delta: Double = RunSettings.standard.delta,
        pickChance: Double = RunSettings.standard.pickChance
    ) {
        self.rate = rate
        level = 1 / delta
        self.pickChance = pickChance
    }

    /// One step for all the answers of one run. A bet is a share `g` of the most the bettor may risk, 1 / rate per
    /// unit of step.
    public mutating func add(run: [Certificate.Answer]) {
        guard let step = Certificate.step(of: run, against: rate, pickChance: pickChance) else { return }
        for (index, bet) in EProcess.grid.enumerated() {
            perBet[index] = max(perBet[index], 1) * (1 - bet / rate * step)
        }
    }

    public var value: Double { perBet.reduce(0, +) / Double(perBet.count) }
    public var isRaised: Bool { value >= level }
}
