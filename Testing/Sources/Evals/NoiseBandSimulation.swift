import Foundation

/// P7: the A/A band of a stage-1 replay (D6 §4.3). The live version runs k more times on the stored trial days; each
/// re-run is compared with the stored run the person saw. A candidate fails when its count is above the band.
///
/// A fact either repeats the stored run's value or moves. Half the facts are flaky (repeat chance uniform in 0.2 to
/// 0.8), half are stable (0.995): R8 saw 3 to 7 of 16 facts move between two runs of one prompt.
public struct NoiseBandSimulation: Sendable {
    public var trials = 2_000
    public var days = 7
    public var factsPerDay = 20
    public var marksPerDay = 10
    public var rightShare = 0.9
    public var flakyShare = 0.5
    public var seed: UInt64 = 20_261_124

    public init() {}

    /// The counts a candidate is judged on.
    public enum Count: String, Sendable, CaseIterable {
        /// Facts that moved, over all facts of the days.
        case factDiff = "fact diff"
        /// Right-marked facts that moved: the regression list.
        case lost = "right-marked lost"
    }

    /// How the band is read from the k re-runs.
    public enum Band: String, Sendable, CaseIterable {
        /// The 95th percentile (nearest rank) of the k counts.
        case empirical
        /// The 95th percentile of the count if each fact moves with its own rate, (moves + 0.5) / (k + 1).
        case perFact = "per fact"
    }

    public struct Result: Sendable {
        /// Share of trials where the candidate failed, by count and band.
        public var fails: [Count: [Band: Double]]
        /// Share of trials where the candidate lost a right-marked fact that did not move in any of the k re-runs.
        public var stableLostFails: Double
        /// The empirical fact-diff band: 10th and 90th percentile over trials, and its true 95th percentile.
        public var bandSpread: (low: Int, high: Int, truth: Int)
    }

    /// `rulesLost` stable right-marked facts that the candidate moves on top of the noise; 0 is the A/A null.
    public func run(reruns k: Int, rulesLost: Int) -> Result {
        var generator = SeededGenerator(seed: seed)
        var fails = Dictionary(
            uniqueKeysWithValues: Count.allCases.map {
                ($0, Dictionary(uniqueKeysWithValues: Band.allCases.map { ($0, 0) }))
            })
        var stableLostFails = 0
        var bands: [Int] = []
        var nullDiffs: [Int] = []
        for _ in 0..<trials {
            let facts = (0..<(days * factsPerDay)).map { index -> Fact in
                let flaky = Double.random(in: 0..<1, using: &generator) < flakyShare
                let marked = index % factsPerDay < marksPerDay
                return Fact(
                    repeatChance: flaky ? Double.random(in: 0.2..<0.8, using: &generator) : 0.995,
                    rightMarked: marked && Double.random(in: 0..<1, using: &generator) < rightShare)
            }
            // Each run draws its value; a run moves a fact when its value differs from the stored run's.
            let stored = facts.map { Double.random(in: 0..<1, using: &generator) < $0.repeatChance }
            let moved: [[Bool]] = (0...k).map { _ in
                zip(facts, stored).map { fact, value in
                    (Double.random(in: 0..<1, using: &generator) < fact.repeatChance) != value
                }
            }
            var candidate = moved[k]
            let reruns = Array(moved[0..<k])
            let targets = facts.indices.filter {
                facts[$0].rightMarked && facts[$0].repeatChance > 0.99 && !candidate[$0]
            }
            for index in targets.prefix(rulesLost) { candidate[index] = true }
            nullDiffs.append(moved[k].filter { $0 }.count)

            for count in Count.allCases {
                let counted = facts.indices.filter { count == .factDiff || facts[$0].rightMarked }
                let tally = { (run: [Bool]) in counted.filter { run[$0] }.count }
                let values = reruns.map(tally)
                let rates = counted.map { index in (Double(reruns.filter { $0[index] }.count) + 0.5) / Double(k + 1) }
                let limits: [Band: Int] = [
                    .empirical: Self.nearestRank(values, 0.95), .perFact: Self.poissonBinomialQuantile(rates, 0.95),
                ]
                if count == .factDiff { bands.append(limits[.empirical]!) }
                for band in Band.allCases where tally(candidate) > limits[band]! { fails[count]![band]! += 1 }
            }
            let stableLost = facts.indices.contains { index in
                facts[index].rightMarked && candidate[index] && !reruns.contains { $0[index] }
            }
            if stableLost { stableLostFails += 1 }
        }
        let share = { (count: Int) in Double(count) / Double(trials) }
        return Result(
            fails: fails.mapValues { $0.mapValues(share) }, stableLostFails: share(stableLostFails),
            bandSpread: (Self.nearestRank(bands, 0.1), Self.nearestRank(bands, 0.9), Self.nearestRank(nullDiffs, 0.95)))
    }

    private struct Fact {
        var repeatChance: Double
        var rightMarked: Bool
    }

    static func nearestRank(_ values: [Int], _ share: Double) -> Int {
        let sorted = values.sorted()
        return sorted[max(0, Int((share * Double(sorted.count)).rounded(.up)) - 1)]
    }

    /// The least count c with P(count <= c) >= `share`, when each event happens on its own with its rate.
    static func poissonBinomialQuantile(_ rates: [Double], _ share: Double) -> Int {
        var law = [1.0]
        for rate in rates {
            var next = Array(repeating: 0.0, count: law.count + 1)
            for (count, chance) in law.enumerated() {
                next[count] += chance * (1 - rate)
                next[count + 1] += chance * rate
            }
            law = next
        }
        var total = 0.0
        for (count, chance) in law.enumerated() {
            total += chance
            if total >= share { return count }
        }
        return law.count - 1
    }
}
