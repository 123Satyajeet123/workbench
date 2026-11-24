import Foundation
import WorkbenchCore

/// The steps the item-level probe compares. Every step reads picks in draw order, and an expired pick counts as wrong
/// (P4). All but `onePerRun` read the same answers.
public enum ItemStep: String, Sendable, CaseIterable {
    /// One step per run, the mean over its answers (the engine as it is): certifies the average run.
    case runMean = "run mean"
    /// One step per run, the sum of its weighted terms over the largest run size.
    case runSum = "sum/cap"
    /// One step per answer, weighted by the design's smallest chance over the answer's chance.
    case item = "item"
    /// One unweighted test per stratum, multiplied and minimised over the strata's allowed rates (union-intersection).
    case strata = "strata UI"
    /// One step per answer, but a run keeps one pick (sampling runs in proportion to size). Its own answers.
    case onePerRun = "one/run"
}

/// The outcome of one step over the trials.
public struct ItemStepOutcome: Sendable {
    /// The day each trial first earned, or nil.
    public var firstEarned: [Int?] = []
    /// Per trial: whether the wealth was at its bar at a time when the wrong rate of all facts drawn so far was at or
    /// above the allowed rate. This is the design-based false-earn: the claim about the facts the machine made.
    public var earnedWhileRealizedHigh: [Bool] = []

    public var designFalseEarn: Double {
        Double(earnedWhileRealizedHigh.filter { $0 }.count) / Double(max(earnedWhileRealizedHigh.count, 1))
    }
}

/// The stratified union-intersection test (Spertus and Stark, arXiv 2207.03379 §3.5; 2409.06680): stratum k bets
/// against "its wrong rate is at least eta_k" with its own unweighted answers; the strata's wealths multiply, and the
/// certificate earns when the product clears the bar for every allocation with sum of share_k · eta_k = allowed rate.
/// Two strata at most; the allocations are a grid on that line, read conservatively between grid points.
struct StratifiedWealth {
    static let bets = (1...9).map { Double($0) / 10 }
    static let gridPoints = 64

    /// Per grid point, per stratum: eta, and per bet the log factor of a right answer (a wrong one is log(1 − bet)).
    private let rightLogs: [[[Double]]]
    private let wrongLogs = bets.map { log(1 - $0) }
    private var answers: [Int]
    private var wrong: [Int]
    private var lastFailed = 0

    init(shares: [Double], allowed: Double) {
        precondition(shares.count <= 2, "the grid search covers two strata")
        answers = Array(repeating: 0, count: shares.count)
        wrong = answers
        let etas: [[Double]]
        if shares.count == 1 {
            etas = [[allowed]]
        } else {
            let (first, second) = (shares[0], shares[1])
            let highest = 0.999
            let low = max(0, (allowed - second * highest) / first)
            let high = min(highest, allowed / first)
            etas = (0..<Self.gridPoints).map { point in
                let eta = low + (high - low) * Double(point) / Double(Self.gridPoints - 1)
                return [eta, (allowed - first * eta) / second]
            }
        }
        rightLogs = etas.map { point in point.map { eta in Self.bets.map { log(1 + $0 * eta / (1 - eta)) } } }
    }

    mutating func add(wrong isWrong: Bool, stratum: Int) {
        answers[stratum] += 1
        if isWrong { wrong[stratum] += 1 }
    }

    /// The log wealth of a stratum at a grid point: the log of the mean over bets of the product of its factors. With
    /// `bound`, the largest bet's log wealth instead, an upper bound that needs no exponent.
    private func logWealth(point: Int, stratum: Int, bound: Bool = false) -> Double {
        let (right, wrongCount) = (Double(answers[stratum] - wrong[stratum]), Double(wrong[stratum]))
        let rights = rightLogs[point][stratum]
        var top = -Double.infinity
        for bet in rights.indices { top = max(top, right * rights[bet] + wrongCount * wrongLogs[bet]) }
        if bound { return top }
        var sum = 0.0
        for bet in rights.indices { sum += exp(right * rights[bet] + wrongCount * wrongLogs[bet] - top) }
        return top + log(sum / Double(rights.count))
    }

    /// Earned when the least product over the allocations clears the bar. A stratum's wealth grows with its eta, so on
    /// each grid interval the product is at least the first stratum's wealth at the interval's low end times the
    /// second's at the interval's high end of eta_1 (where eta_2 is lowest). The interval that failed last is tried
    /// first, since it most often fails again.
    mutating func isEarned(threshold: Double) -> Bool {
        let bar = log(threshold)
        guard rightLogs.count > 1 else { return logWealth(point: 0, stratum: 0) >= bar }
        if fails(interval: lastFailed, below: bar, bound: false) { return false }
        for point in 0..<(rightLogs.count - 1)
        where fails(interval: point, below: bar, bound: true) || fails(interval: point, below: bar, bound: false) {
            lastFailed = point
            return false
        }
        return true
    }

    private func fails(interval point: Int, below bar: Double, bound: Bool) -> Bool {
        logWealth(point: point, stratum: 0, bound: bound) + logWealth(point: point + 1, stratum: 1, bound: bound) < bar
    }
}

/// Picks of one stream, entered in draw order: a run enters when all its picks are answered or expired, and the
/// cursor waits at the oldest open run (P4).
struct DrawOrderQueue {
    typealias AskedRun = (closes: Int, run: DrawnRun, answered: [Bool])
    private var drawn: [AskedRun] = []
    private var cursor = 0

    mutating func draw(_ run: DrawnRun, day: Int, expiryDays: Int, answered: [Bool]) {
        drawn.append((answered.allSatisfy { $0 } ? day : day + expiryDays, run, answered))
    }

    /// The runs that enter on this day, in draw order.
    mutating func entering(on day: Int) -> ArraySlice<AskedRun> {
        let start = cursor
        while cursor < drawn.count, drawn[cursor].closes <= day { cursor += 1 }
        return drawn[start..<cursor]
    }
}

/// The wealths of the steps that read the shared stream, and which of them are at their bar now.
struct SharedStepWealths {
    private let design: PickDesign
    private var runMean = Certificate.Wealth()
    private var runSum: CertificateReader
    private var item = Certificate.Wealth()
    private var strata: StratifiedWealth
    private(set) var atBar: Set<ItemStep> = []
    /// Steps that were at their bar at some point today: an item step may cross it and fall back within one run.
    private(set) var reachedBar: Set<ItemStep> = []

    init(design: PickDesign, largestRun: Int) {
        self.design = design
        runSum = CertificateReader(withDriftRestarts: false, stepCap: largestRun)
        strata = StratifiedWealth(shares: design.strata.map(\.share), allowed: RunSettings.standard.allowedWrong)
    }

    /// The answers of one run, in draw order; `wrong` already counts an expired pick as wrong.
    mutating func add(_ answers: [(pick: Pick, wrong: Bool)]) {
        guard !answers.isEmpty else { return }
        let weighted = answers.map { Certificate.Answer(wrong: $0.wrong, chance: design.engineChance($0.pick.chance)) }
        runMean.add(run: weighted)
        mark(.runMean, runMean.value >= RunSettings.standard.threshold)
        mark(.runSum, runSum.add(run: weighted))
        for (answer, entry) in zip(weighted, answers) {
            item.add(answer)
            mark(.item, item.value >= RunSettings.standard.threshold)
            strata.add(wrong: entry.wrong, stratum: entry.pick.stratum)
            mark(.strata, strata.isEarned(threshold: RunSettings.standard.threshold))
        }
    }

    mutating func startDay() { reachedBar = atBar }

    private mutating func mark(_ step: ItemStep, _ isAtBar: Bool) {
        if isAtBar {
            atBar.insert(step)
            reachedBar.insert(step)
        } else {
            atBar.remove(step)
        }
    }
}

/// The facts drawn so far in one stream, picked or not: the population the design-based claim is about.
struct RealizedFacts {
    private var facts = 0
    private var wrong = 0

    mutating func add(_ run: DrawnRun) {
        facts += run.facts
        wrong += run.wrongFacts
    }

    var isAtOrAboveAllowed: Bool { Double(wrong) >= RunSettings.standard.allowedWrong * Double(facts) }
}

/// The item-level probe: which step certifies the wrong rate of facts, not of runs, under unequal known chances and
/// run clustering, and how fast. Same stream, seed and trial count as P3; P4's rule in every step.
public struct ItemLevelSimulation: Sendable {
    public var trials = 2_000
    public var horizonDays = 365
    public var expiryDays = 14
    public var seed: UInt64 = 20_261_124

    public init() {}

    public func run(
        _ design: PickDesign, population: AuditPopulation, picksPerDay: Double, concentration: Double? = nil,
        skipWrong: Double = 0, skipRight: Double = 0
    ) -> [ItemStep: ItemStepOutcome] {
        var shared = AuditStream(
            design: design, population: population, picksPerDay: picksPerDay, concentration: concentration, seed: seed)
        var thinned = shared
        thinned.keepsOnePickPerRun = true
        let smallestKept = thinned.smallestKeptChance
        let largestRun = population.kinds.map(\.size).max() ?? 1
        let tracksRealized = population.itemWrongRate >= RunSettings.standard.allowedWrong
        var outcomes = Dictionary(uniqueKeysWithValues: ItemStep.allCases.map { ($0, ItemStepOutcome()) })
        for _ in 0..<trials {
            var wealths = SharedStepWealths(design: design, largestRun: largestRun)
            var onePerRun = Certificate.Wealth()
            var queues = (shared: DrawOrderQueue(), thinned: DrawOrderQueue())
            var realized = (shared: RealizedFacts(), thinned: RealizedFacts())
            var first: [ItemStep: Int] = [:]
            var high: Set<ItemStep> = []
            for day in 1...horizonDays {
                for run in shared.drawnDay() {
                    let answered = Self.answered(run, skipWrong, skipRight, &shared)
                    queues.shared.draw(run, day: day, expiryDays: expiryDays, answered: answered)
                }
                for run in thinned.drawnDay() {
                    let answered = Self.answered(run, skipWrong, skipRight, &thinned)
                    queues.thinned.draw(run, day: day, expiryDays: expiryDays, answered: answered)
                }
                wealths.startDay()
                for asked in queues.shared.entering(on: day) {
                    realized.shared.add(asked.run)
                    wealths.add(Self.counted(asked))
                    if realized.shared.isAtOrAboveAllowed { high.formUnion(wealths.atBar) }
                }
                for step in wealths.reachedBar where first[step] == nil { first[step] = day }
                for asked in queues.thinned.entering(on: day) {
                    realized.thinned.add(asked.run)
                    for entry in Self.counted(asked) {
                        let share = min(1, smallestKept / entry.pick.chance)
                        onePerRun.add(
                            Certificate.Answer(wrong: entry.wrong, chance: RunSettings.standard.pickChance / share))
                        if onePerRun.value >= RunSettings.standard.threshold, first[.onePerRun] == nil {
                            first[.onePerRun] = day
                        }
                    }
                    if onePerRun.value >= RunSettings.standard.threshold, realized.thinned.isAtOrAboveAllowed {
                        high.insert(.onePerRun)
                    }
                }
                if !tracksRealized, first.count == ItemStep.allCases.count { break }
            }
            for step in ItemStep.allCases {
                outcomes[step]!.firstEarned.append(first[step])
                outcomes[step]!.earnedWhileRealizedHigh.append(high.contains(step))
            }
        }
        return outcomes
    }

    /// Each pick of a run with the answer the certificate counts: an expired pick counts as wrong (P4).
    private static func counted(_ asked: DrawOrderQueue.AskedRun) -> [(pick: Pick, wrong: Bool)] {
        zip(asked.run.picks, asked.answered).map { pick, answered in (pick, pick.wrong || !answered) }
    }

    /// Whether the person answers each pick of a run: a wrong pick is skipped with `skipWrong`, a right one with
    /// `skipRight`.
    private static func answered(
        _ run: DrawnRun, _ skipWrong: Double, _ skipRight: Double, _ stream: inout AuditStream
    ) -> [Bool] {
        run.picks.map { Double.random(in: 0..<1, using: &stream.generator) >= ($0.wrong ? skipWrong : skipRight) }
    }
}
