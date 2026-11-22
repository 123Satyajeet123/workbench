import Foundation

public struct Certificate: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        case needsMore(Int)
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

    public static func upperBound(wrong: Int, of answers: Int, confidence: Double = confidence) -> Double {
        guard answers > 0, wrong < answers else { return 1 }
        var (low, high) = (0.0, 1.0)
        for _ in 0..<100 {
            let middle = (low + high) / 2
            if binomialCDF(wrong, answers, middle) > 1 - confidence { low = middle } else { high = middle }
        }
        return high
    }

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
