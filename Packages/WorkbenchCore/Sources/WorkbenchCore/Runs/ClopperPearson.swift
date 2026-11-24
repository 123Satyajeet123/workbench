import Foundation

/// The exact binomial upper bound on a rate (Clopper-Pearson). It is valid for one look at a fixed number of answers.
public enum ClopperPearson {
    /// The largest wrong-rate p with P(at most `wrong` wrong in `answers` | p) ≥ 1 − confidence.
    public static func upperBound(wrong: Int, of answers: Int, confidence: Double = RunSettings.standard.confidence)
        -> Double
    {
        guard answers > 0, wrong < answers else { return 1 }
        var (low, high) = (0.0, 1.0)
        for _ in 0..<100 {
            let middle = (low + high) / 2
            if binomialCDF(wrong, answers, middle) > 1 - confidence { low = middle } else { high = middle }
        }
        return high
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
