import Foundation

/// Whether a helper has earned trust, from its audit answers on held-out days in the order they were given. A bettor
/// bets, answer after answer, that the helper's wrong rate is above `allowedWrong`. Each right answer makes the bettor
/// poorer and each wrong one richer, so the bettor's wealth is an e-value against "wrong more than allowedWrong"
/// (Waudby-Smith and Ramdas, arXiv 2010.09686). "Earned" means the wealth is at least 1 / (1 − `confidence`). When the
/// true wrong rate is `allowedWrong` or higher, the chance that the wealth ever reaches that bar is at most
/// 1 − `confidence` (Ville's inequality), however often the certificate is read.
///
/// An answer weighs one over the chance its item had of being picked. `AuditPolicy` gives every item the same chance,
/// so every answer weighs `heaviestWeight` and the weights change nothing; they keep the test valid for answers picked
/// under another chance. A weight above `heaviestWeight` counts as `heaviestWeight`.
public struct Certificate: Sendable, Equatable {
    public enum Status: Sendable, Equatable, Codable {
        /// At least this many more answers, all right and all at the heaviest weight, before it is earned.
        case needsMore(Int)
        /// The wrong rate is at most this, with `confidence`, however often the answers were read.
        case earned(bound: Double)
    }

    public struct Answer: Sendable, Equatable {
        public var wrong: Bool
        /// The chance the answered item had of being the one picked, above 0 and at most 1.
        public var chance: Double

        public init(wrong: Bool, chance: Double) {
            self.wrong = wrong
            self.chance = chance
        }

        /// The weight over the heaviest weight: above 0 and at most 1.
        var share: Double { min(1 / chance, Certificate.heaviestWeight) / Certificate.heaviestWeight }
    }

    /// The wealth of a bettor against "wrong at most `rate`", averaged over a grid of bet sizes (a mean of
    /// e-processes is an e-process). A bet is a share `g` of the most the bettor may risk, 1 / (1 − rate) per unit of
    /// weight share, so the wealth stays above zero for any answer.
    public struct Wealth: Sendable, Equatable {
        private let rate: Double
        private var perBet = Array(repeating: 1.0, count: EProcess.grid.count)

        public init(against rate: Double = Certificate.allowedWrong) {
            self.rate = rate
        }

        public mutating func add(_ answer: Answer) {
            let outcome = answer.wrong ? 1.0 : 0.0
            for (index, bet) in EProcess.grid.enumerated() {
                perBet[index] *= 1 + bet / (1 - rate) * answer.share * (rate - outcome)
            }
        }

        public var value: Double { perBet.reduce(0, +) / Double(perBet.count) }
    }

    public static let allowedWrong = 0.1
    public static let confidence = 0.9
    public static let heaviestWeight = 1 / AuditPolicy.pickChance
    public static var threshold: Double { 1 / (1 - confidence) }

    public var answers: [Answer]

    public init(answers: [Answer] = []) {
        self.answers = answers
    }

    public var status: Status {
        let wealth = wealth(against: Self.allowedWrong)
        return wealth.value >= Self.threshold
            ? .earned(bound: upperBound) : .needsMore(rightAnswersToEarn(from: wealth))
    }

    private func wealth(against rate: Double) -> Wealth {
        answers.reduce(into: Wealth(against: rate)) { $0.add($1) }
    }

    private func rightAnswersToEarn(from start: Wealth) -> Int {
        var wealth = start
        var more = 0
        while wealth.value < Self.threshold {
            wealth.add(Answer(wrong: false, chance: 1 / Self.heaviestWeight))
            more += 1
        }
        return more
    }

    /// The least wrong rate the bettor can still bet against with enough wealth to count: the upper end of the
    /// confidence sequence. The wealth only grows with the rate, so a bisection finds it below `allowedWrong`.
    private var upperBound: Double {
        var (low, high) = (0.0, Self.allowedWrong)
        for _ in 0..<40 {
            let middle = (low + high) / 2
            if wealth(against: middle).value >= Self.threshold { high = middle } else { low = middle }
        }
        return high
    }
}
