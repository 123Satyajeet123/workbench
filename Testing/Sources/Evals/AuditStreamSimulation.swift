import Foundation
import WorkbenchCore

/// One stratum of a pick design: its share of the items, the chance each of its items is picked, and its wrong rate as
/// a factor of the run's rate. Over all items the factors average to 1, so the item wrong rate stays as set.
public struct Stratum: Sendable {
    public var share: Double
    public var chance: Double
    public var wrongFactor = 1.0

    public init(share: Double, chance: Double) {
        self.share = share
        self.chance = chance
    }
}

/// Where the wrong items of a design sit.
public enum WrongPlacement: String, Sendable, CaseIterable {
    case even = "same rate in every stratum"
    case lowestChance = "all wrong in the lowest-chance stratum"
    case highestChance = "all wrong in the highest-chance stratum"
}

/// A pick design (research 86 Decision 7): strata, each with its own chance. Its smallest chance has weight 1.
public struct PickDesign: Sendable {
    public var name: String
    public var strata: [Stratum]

    public init(_ name: String, _ strata: [Stratum]) {
        self.name = name
        self.strata = strata
    }

    public var smallestChance: Double { strata.map(\.chance).min() ?? 1 }
    var meanChance: Double { strata.map { $0.share * $0.chance }.reduce(0, +) }

    /// The chance as the certificate engine must see it so that the design's smallest chance has share 1. The engine
    /// fixes its heaviest weight at 1 / `AuditPolicy.pickChance` (Certificate.swift:82); D6 §4.1 moves it to the design.
    func engineChance(_ chance: Double) -> Double { chance * AuditPolicy.pickChance / smallestChance }

    public func placing(_ placement: WrongPlacement) -> PickDesign {
        var placed = self
        let target: Double? =
            switch placement {
            case .even: nil
            case .lowestChance: smallestChance
            case .highestChance: strata.map(\.chance).max()
            }
        guard let target else { return placed }
        let share = strata.filter { $0.chance == target }.map(\.share).reduce(0, +)
        for index in placed.strata.indices {
            placed.strata[index].wrongFactor = placed.strata[index].chance == target ? 1 / share : 0
        }
        return placed
    }
}

/// A picked item: whether it is wrong and the chance it had.
public struct Pick: Sendable {
    public var wrong: Bool
    public var chance: Double
}

/// Days of runs whose items are picked by a design. Run sizes and their wrong rates come from an `AuditPopulation`;
/// runs per day are set so that the expected picks per day is `picksPerDay`. With a `concentration`, each run draws
/// its own wrong rate from a Beta law around its kind's rate, so the items of one run are alike.
public struct AuditStream {
    public var design: PickDesign
    public var population: AuditPopulation
    public var picksPerDay: Double
    public var concentration: Double?
    var generator: SeededGenerator

    public init(
        design: PickDesign, population: AuditPopulation, picksPerDay: Double, concentration: Double? = nil,
        seed: UInt64
    ) {
        self.design = design
        self.population = population
        self.picksPerDay = picksPerDay
        self.concentration = concentration
        generator = SeededGenerator(seed: seed)
    }

    private var meanRunSize: Double {
        population.kinds.map { $0.share * Double($0.size) }.reduce(0, +)
    }

    /// The picks of each run of one day; a run with no pick is left out.
    public mutating func day() -> [[Pick]] {
        let runs = generator.poisson(mean: picksPerDay / (meanRunSize * design.meanChance))
        return (0..<runs).map { _ in run() }.filter { !$0.isEmpty }
    }

    private mutating func run() -> [Pick] {
        let kind = population.kinds[generator.index(byShare: population.kinds.map(\.share))]
        let rate =
            concentration.map { generator.beta(mean: kind.wrongRate, concentration: $0) } ?? kind.wrongRate
        return (0..<kind.size).compactMap { _ in
            let stratum = design.strata[generator.index(byShare: design.strata.map(\.share))]
            let wrong = Double.random(in: 0..<1, using: &generator) < rate * stratum.wrongFactor
            guard Double.random(in: 0..<1, using: &generator) < stratum.chance else { return nil }
            return Pick(wrong: wrong, chance: stratum.chance)
        }
    }
}

/// The certificate as the app reads it (Certificate.status): the wealth counts runs since the drift alarm last fired,
/// and "earned" means the wealth reached its bar after that. Built from the engine's own `Wealth` and `DriftAlarm`.
public struct CertificateReader {
    public var withDriftRestarts: Bool
    /// When set, a run's step is the sum of its answers' terms over this cap, not their mean: a candidate step (P3)
    /// that weighs each item alike. Simulated by filling the run up to the cap with answers of weight 0.
    public var stepCap: Int?
    private var wealth = Certificate.Wealth()
    private var alarm = DriftAlarm()

    public init(withDriftRestarts: Bool, stepCap: Int? = nil) {
        self.withDriftRestarts = withDriftRestarts
        self.stepCap = stepCap
    }

    /// Adds one run and tells whether the wealth is at its bar now.
    public mutating func add(run: [Certificate.Answer]) -> Bool {
        var counted = run
        if let stepCap {
            precondition(run.count <= stepCap, "a run has more answers than the step cap")
            counted += Array(
                repeating: Certificate.Answer(wrong: false, chance: .greatestFiniteMagnitude),
                count: stepCap - run.count)
        }
        wealth.add(run: counted)
        if withDriftRestarts {
            alarm.add(run: counted)
            if alarm.isRaised {
                (wealth, alarm) = (Certificate.Wealth(), DriftAlarm())
            }
        }
        return wealth.value >= Certificate.threshold
    }
}

/// The ways P3 reads the same answers.
public enum AuditReading: String, Sendable, CaseIterable {
    /// Weighted by the design, the step a mean over the run (the engine as it is).
    case weighted
    /// The same, with the drift alarm's restarts, as `Certificate.status` reads it.
    case withRestarts = "+restarts"
    /// Every answer at share 1, as if all chances were equal.
    case unweighted = "no weights"
    /// Weighted, the step a sum over the run divided by the largest run size.
    case runSum = "sum/cap"
}

/// P3: how often a design's certificate earns under the null, and how many days it takes when the helper is good.
public struct WeightedAuditSimulation: Sendable {
    public var trials = 2_000
    public var horizonDays = 365
    public var seed: UInt64 = 20_261_124

    public init() {}

    /// For each reading, the day each trial first earned (nil when not within the horizon), read after every run.
    public func run(
        _ design: PickDesign, population: AuditPopulation, picksPerDay: Double, concentration: Double? = nil
    ) -> [AuditReading: [Int?]] {
        var stream = AuditStream(
            design: design, population: population, picksPerDay: picksPerDay, concentration: concentration, seed: seed)
        let cap = population.kinds.map(\.size).max() ?? 1
        var result = Dictionary(uniqueKeysWithValues: AuditReading.allCases.map { ($0, [Int?]()) })
        for _ in 0..<trials {
            var readers: [AuditReading: CertificateReader] = [
                .weighted: CertificateReader(withDriftRestarts: false),
                .withRestarts: CertificateReader(withDriftRestarts: true),
                .unweighted: CertificateReader(withDriftRestarts: false),
                .runSum: CertificateReader(withDriftRestarts: false, stepCap: cap),
            ]
            var earned: [AuditReading: Int] = [:]
            for day in 1...horizonDays where earned.count < AuditReading.allCases.count {
                for picks in stream.day() {
                    let weighted = picks.map {
                        Certificate.Answer(wrong: $0.wrong, chance: design.engineChance($0.chance))
                    }
                    let flat = picks.map { Certificate.Answer(wrong: $0.wrong, chance: AuditPolicy.pickChance) }
                    for reading in AuditReading.allCases where earned[reading] == nil {
                        if readers[reading]!.add(run: reading == .unweighted ? flat : weighted) {
                            earned[reading] = day
                        }
                    }
                }
            }
            for reading in AuditReading.allCases { result[reading]!.append(earned[reading]) }
        }
        return result
    }
}

/// How the certificate treats a pick the person never answers, and in which order closed runs enter it. A run closes
/// when its last pick is answered, or `expiryDays` after it was drawn.
public enum NonResponseRule: String, Sendable, CaseIterable {
    /// Today (Quality.swift:148-154): a run enters when every pick is answered, so it may wait for ever.
    case waitForAll = "wait (today)"
    /// A run enters when it closes, with its answered picks only.
    case answeredOnly = "answered, close order"
    /// A run enters when it closes; an unanswered pick counts as wrong.
    case expiredIsWrong = "expired wrong, close"
    /// Runs enter in the order they were drawn: the certificate waits at the oldest open run.
    case answeredOnlyInDrawOrder = "answered, draw order"
    case expiredIsWrongInDrawOrder = "expired wrong, draw"

    var inDrawOrder: Bool { self == .answeredOnlyInDrawOrder || self == .expiredIsWrongInDrawOrder }
    var expiredIsWrong: Bool { self == .expiredIsWrong || self == .expiredIsWrongInDrawOrder }
}

/// P4: picks the person skips. A wrong pick is skipped with `skipWrong`, a right one with `skipRight`.
public struct NonResponseSimulation: Sendable {
    public var trials = 2_000
    public var horizonDays = 120
    public var expiryDays = 14
    public var seed: UInt64 = 20_261_124

    public init() {}

    private typealias AskedRun = (closes: Int, picks: [(pick: Pick, answered: Bool)])

    /// For each rule, the day the certificate first earned in each trial (nil when not within the horizon).
    public func run(
        _ design: PickDesign, population: AuditPopulation, picksPerDay: Double, skipWrong: Double, skipRight: Double
    ) -> [NonResponseRule: [Int?]] {
        var stream = AuditStream(design: design, population: population, picksPerDay: picksPerDay, seed: seed)
        var earned = Dictionary(uniqueKeysWithValues: NonResponseRule.allCases.map { ($0, [Int?]()) })
        for _ in 0..<trials {
            var readers = Dictionary(
                uniqueKeysWithValues: NonResponseRule.allCases.map { ($0, CertificateReader(withDriftRestarts: true)) })
            var first: [NonResponseRule: Int] = [:]
            var drawn: [AskedRun] = []
            var closing: [Int: [AskedRun]] = [:]
            var cursor = Dictionary(uniqueKeysWithValues: NonResponseRule.allCases.map { ($0, 0) })
            for day in 1...horizonDays {
                for picks in stream.day() {
                    let asked = picks.map { pick in
                        let skip = pick.wrong ? skipWrong : skipRight
                        return (pick: pick, answered: Double.random(in: 0..<1, using: &stream.generator) >= skip)
                    }
                    let run = (closes: asked.allSatisfy(\.answered) ? day : day + expiryDays, picks: asked)
                    drawn.append(run)
                    closing[run.closes, default: []].append(run)
                }
                let closed = closing.removeValue(forKey: day) ?? []
                for rule in NonResponseRule.allCases where first[rule] == nil {
                    var entering = closed
                    if rule == .waitForAll { entering = closed.filter { $0.picks.allSatisfy(\.answered) } }
                    if rule.inDrawOrder {
                        let start = cursor[rule]!
                        var end = start
                        while end < drawn.count, drawn[end].closes <= day { end += 1 }
                        entering = Array(drawn[start..<end])
                        cursor[rule] = end
                    }
                    for run in entering {
                        guard readers[rule]!.add(run: answers(of: run, rule: rule, design: design)) else { continue }
                        first[rule] = day
                        break
                    }
                }
            }
            for rule in NonResponseRule.allCases { earned[rule]!.append(first[rule]) }
        }
        return earned
    }

    private func answers(of run: AskedRun, rule: NonResponseRule, design: PickDesign) -> [Certificate.Answer] {
        run.picks.compactMap { asked in
            let chance = design.engineChance(asked.pick.chance)
            if asked.answered { return Certificate.Answer(wrong: asked.pick.wrong, chance: chance) }
            return rule.expiredIsWrong ? Certificate.Answer(wrong: true, chance: chance) : nil
        }
    }
}

extension SeededGenerator {
    /// Knuth's method; fine for the small means used here.
    public mutating func poisson(mean: Double) -> Int {
        let limit = exp(-mean)
        var (count, product) = (0, Double.random(in: 0..<1, using: &self))
        while product > limit {
            count += 1
            product *= Double.random(in: 0..<1, using: &self)
        }
        return count
    }

    /// An index drawn with chance proportional to its share.
    public mutating func index(byShare shares: [Double]) -> Int {
        var pick = Double.random(in: 0..<1, using: &self) * shares.reduce(0, +)
        for (index, share) in shares.enumerated() {
            if pick < share { return index }
            pick -= share
        }
        return shares.count - 1
    }
}

/// Summaries of first-earned days over trials.
extension Array where Element == Int? {
    /// The share of trials that earned at all, or by `day`.
    public func shareEarned(by day: Int = .max) -> Double {
        Double(compactMap { $0 }.filter { $0 <= day }.count) / Double(Swift.max(count, 1))
    }

    /// The median day to earn, or nil when fewer than half earned.
    public var medianDay: Int? {
        let sorted = map { $0 ?? .max }.sorted()
        let middle = sorted[sorted.count / 2]
        return middle == .max ? nil : middle
    }
}
