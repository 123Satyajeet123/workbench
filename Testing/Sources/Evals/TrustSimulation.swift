import Foundation
import WorkbenchCore

/// A random source that a seed fixes, so every run of the simulation gives the same numbers (SplitMix64).
public struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}

/// The ways a certificate may judge audit answers.
public enum TrustRule: String, Sendable, CaseIterable {
    /// The old rule: the exact binomial bound on the counts, read after every answer.
    case fixedBound = "old: fixed-n bound"
    /// The new rule: the betting test with importance weights.
    case betting = "new: betting, weighted"
    /// The betting test with every answer at the heaviest weight, as if all picks had the same chance.
    case bettingWithoutWeights = "betting, no weights"
}

/// How the app picks the items it asks about.
public enum PickPolicy: Sendable {
    /// One item of each reading, so its chance is one over the size of its reading.
    case onePerReading
    /// Each item on its own with the same chance, whatever its reading.
    case eachItem(chance: Double)
}

/// Readings of different sizes. The wrong rate may differ by size; the item-level rate is what the certificate speaks of.
public struct AuditPopulation: Sendable {
    public struct Kind: Sendable {
        public var size: Int
        public var share: Double
        public var wrongRate: Double
    }

    public var kinds: [Kind]

    /// Every reading has the same size, so the weights carry no information.
    public static func equal(size: Int, wrongRate: Double) -> AuditPopulation {
        AuditPopulation(kinds: [Kind(size: size, share: 1, wrongRate: wrongRate)])
    }

    /// Reading sizes and the share of readings of each size.
    public typealias SizeMix = [(size: Int, share: Double)]
    public static let usualSizes: SizeMix = [(1, 0.30), (2, 0.25), (4, 0.20), (6, 0.15), (10, 0.10)]
    public static let largeSizes: SizeMix = [(1, 0.25), (2, 0.25), (5, 0.20), (10, 0.15), (20, 0.10), (40, 0.05)]

    /// A mix of reading sizes, each item wrong with the same chance.
    public static func mixed(itemWrongRate: Double, sizes: SizeMix = usualSizes) -> AuditPopulation {
        AuditPopulation(kinds: sizes.map { Kind(size: $0.size, share: $0.share, wrongRate: itemWrongRate) })
    }

    /// A mix of reading sizes where big readings are wrong more often. The item-level wrong rate is `itemWrongRate`;
    /// the average over readings of the share wrong is lower.
    public static func bigReadingsWorse(itemWrongRate: Double, sizes: SizeMix = usualSizes) -> AuditPopulation {
        let items = sizes.map { Double($0.size) * $0.share }.reduce(0, +)
        let itemSquares = sizes.map { Double($0.size * $0.size) * $0.share }.reduce(0, +)
        return AuditPopulation(
            kinds: sizes.map {
                Kind(size: $0.size, share: $0.share, wrongRate: itemWrongRate * Double($0.size) * items / itemSquares)
            })
    }

    public var itemWrongRate: Double {
        kinds.map { Double($0.size) * $0.share * $0.wrongRate }.reduce(0, +)
            / kinds.map { Double($0.size) * $0.share }.reduce(0, +)
    }

    /// The answer to one audited item. Under `onePerReading` a reading is drawn by its share and its one item is
    /// asked about. Under `eachItem` an asked item is any item, so a reading is drawn by its share of all items.
    func draw(_ policy: PickPolicy, using generator: inout SeededGenerator) -> Certificate.Answer {
        let weights: [Double]
        switch policy {
        case .onePerReading: weights = kinds.map(\.share)
        case .eachItem: weights = kinds.map { $0.share * Double($0.size) }
        }
        var pick = Double.random(in: 0..<1, using: &generator) * weights.reduce(0, +)
        var kind = kinds[kinds.count - 1]
        for (candidate, weight) in zip(kinds, weights) {
            if pick < weight {
                kind = candidate
                break
            }
            pick -= weight
        }
        let chance =
            switch policy {
            case .onePerReading: 1 / Double(kind.size)
            case .eachItem(let chance): chance
            }
        return Certificate.Answer(wrong: Double.random(in: 0..<1, using: &generator) < kind.wrongRate, chance: chance)
    }
}

/// How often and how fast each rule says "earned" when it is read after every answer, on synthetic answers only.
public struct TrustSimulation: Sendable {
    public var runs = 4_000
    public var policy = PickPolicy.eachItem(chance: AuditPolicy.pickChance)
    public var horizon = 300
    public var seed: UInt64 = 20_261_123

    public init() {}

    public struct Result: Sendable {
        /// For each run, the answer after which the rule first said "earned", or nil when it did not within the horizon.
        public var firstEarned: [Int?]

        /// The share of runs that ever said "earned".
        public var everEarned: Double { Double(firstEarned.compactMap { $0 }.count) / Double(firstEarned.count) }

        /// The median answers to earn, or nil when fewer than half the runs earned within the horizon.
        public var median: Int? {
            let sorted = firstEarned.map { $0 ?? Int.max }.sorted()
            let middle = sorted[sorted.count / 2]
            return middle == Int.max ? nil : middle
        }
    }

    /// All rules read the same answers. Each run starts from the same seed offset, so a table row is reproducible.
    public func run(_ population: AuditPopulation) -> [TrustRule: Result] {
        var generator = SeededGenerator(seed: seed)
        var earned = Dictionary(uniqueKeysWithValues: TrustRule.allCases.map { ($0, [Int?]()) })
        var fixedBound = FixedBoundCache()
        for _ in 0..<runs {
            let answers = (0..<horizon).map { _ in population.draw(policy, using: &generator) }
            earned[.fixedBound]?.append(fixedBound.firstEarned(answers))
            earned[.betting]?.append(Self.firstEarned(answers, weighted: true))
            earned[.bettingWithoutWeights]?.append(Self.firstEarned(answers, weighted: false))
        }
        return earned.mapValues(Result.init)
    }

    private static func firstEarned(_ answers: [Certificate.Answer], weighted: Bool) -> Int? {
        var wealth = Certificate.Wealth()
        for (index, answer) in answers.enumerated() {
            let counted =
                weighted ? answer : Certificate.Answer(wrong: answer.wrong, chance: 1 / Certificate.heaviestWeight)
            wealth.add(counted)
            if wealth.value >= Certificate.threshold { return index + 1 }
        }
        return nil
    }

    /// The old rule asks for the exact bound at every count, so each (wrong, answers) pair is worked out once.
    private struct FixedBoundCache {
        private var earned: [Int: Bool] = [:]

        mutating func firstEarned(_ answers: [Certificate.Answer]) -> Int? {
            var wrong = 0
            for (index, answer) in answers.enumerated() {
                if answer.wrong { wrong += 1 }
                let key = wrong * 100_000 + index + 1
                let isEarned =
                    earned[key]
                    ?? (ClopperPearson.upperBound(wrong: wrong, of: index + 1) <= Certificate.allowedWrong)
                earned[key] = isEarned
                if isEarned { return index + 1 }
            }
            return nil
        }
    }
}
