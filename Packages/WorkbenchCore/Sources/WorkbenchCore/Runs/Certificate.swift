import Foundation

/// Whether a helper has earned trust: from audit answers on held-out days, an exact binomial bound (Clopper-Pearson)
/// on how often its items are wrong. "Earned" means the bound is at most `allowedWrong` with chance `confidence` —
/// a finite-sample guarantee for an item picked the way audits pick, not an average that hides a bad streak.
public struct Certificate: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        /// At least this many more answers, all right, before the bound can reach the allowed rate.
        case needsMore(Int)
        /// The bound is at or below the allowed rate.
        case earned(bound: Double)
    }

    public static let allowedWrong = 0.1
    public static let confidence = 0.9

    public var answers: Int
    public var wrong: Int

    public init(answers: Int, wrong: Int) {
        self.answers = answers
        self.wrong = wrong
    }

    public var status: Status {
        let bound = Self.upperBound(wrong: wrong, of: answers)
        if bound <= Self.allowedWrong { return .earned(bound: bound) }
        return .needsMore(max(1, Self.fewestAnswers(wrong: wrong) - answers))
    }

    /// The largest wrong-rate p with P(at most `wrong` wrong in `answers` | p) ≥ 1 − confidence.
    public static func upperBound(wrong: Int, of answers: Int, confidence: Double = confidence) -> Double {
        guard answers > 0, wrong < answers else { return 1 }
        var (low, high) = (0.0, 1.0)
        for _ in 0..<100 {
            let middle = (low + high) / 2
            if binomialCDF(wrong, answers, middle) > 1 - confidence { low = middle } else { high = middle }
        }
        return high
    }

    /// The fewest answers with `wrong` of them wrong that can still earn the certificate.
    public static func fewestAnswers(wrong: Int) -> Int {
        var answers = wrong + 1
        while upperBound(wrong: wrong, of: answers) > allowedWrong { answers += 1 }
        return answers
    }

    private static func binomialCDF(_ k: Int, _ n: Int, _ p: Double) -> Double {
        guard p > 0 else { return 1 }
        guard p < 1 else { return k >= n ? 1 : 0 }
        let (logP, logQ) = (log(p), log1p(-p))
        return (0...k).reduce(0) { sum, i in
            let logChoose = lgamma(Double(n + 1)) - lgamma(Double(i + 1)) - lgamma(Double(n - i + 1))
            return sum + exp(logChoose + Double(i) * logP + Double(n - i) * logQ)
        }
    }
}
