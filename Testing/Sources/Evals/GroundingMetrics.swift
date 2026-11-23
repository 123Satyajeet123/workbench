import Foundation
import WorkbenchCore

/// The control of probe P-J1: how much of the claim's words are in the premise. It knows no meaning, so a verifier that
/// does not beat it adds nothing.
public struct LexicalOverlap: SupportScorer {
    public init() {}

    public var identity: GroundingIdentity { GroundingIdentity(name: "lexical-overlap") }

    public func support(of claim: String, premise: String) async throws -> Double {
        let wanted = Self.words(claim)
        guard !wanted.isEmpty else { return 0 }
        let held = Set(Self.words(premise))
        return Double(wanted.filter(held.contains).count) / Double(wanted.count)
    }

    static func words(_ text: String) -> [String] {
        text.comparable.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}

/// Numbers of one arm of the probe: scores of supported pairs and of unsupported pairs.
public struct ScoredPairs: Sendable {
    public var supported: [Double]
    public var unsupported: [Double]

    public init(supported: [Double], unsupported: [Double]) {
        self.supported = supported
        self.unsupported = unsupported
    }

    /// The chance that a supported pair scores above an unsupported one; ties count half.
    public var auroc: Double? {
        guard !supported.isEmpty, !unsupported.isEmpty else { return nil }
        let wins = supported.reduce(0.0) { total, high in
            total + unsupported.reduce(0.0) { $0 + (high > $1 ? 1 : high == $1 ? 0.5 : 0) }
        }
        return wins / Double(supported.count * unsupported.count)
    }

    /// The 90% interval of the AUROC (Hanley and McNeil, 1982): the standard error from the two counts and the AUROC.
    public var interval90: ClosedRange<Double>? {
        guard let area = auroc else { return nil }
        let (positives, negatives) = (Double(supported.count), Double(unsupported.count))
        let q1 = area / (2 - area)
        let q2 = 2 * area * area / (1 + area)
        let variance =
            (area * (1 - area) + (positives - 1) * (q1 - area * area) + (negatives - 1) * (q2 - area * area))
            / (positives * negatives)
        let margin = 1.645 * variance.squareRoot()
        return max(0, area - margin)...min(1, area + margin)
    }

    /// The band the decision rule gives: `passFrom` is the 90th percentile of the unsupported scores, `failBelow` the 10th
    /// percentile of the supported scores, and when they cross both take `passFrom`.
    public var band: ScoreBand? {
        guard !supported.isEmpty, !unsupported.isEmpty else { return nil }
        let pass = Self.percentile(unsupported, 0.9)
        let fail = Self.percentile(supported, 0.1)
        return ScoreBand(failBelow: min(fail, pass), passFrom: pass)
    }

    /// What a band does to the pairs: how many unsupported pass, how many supported fail, and how many are left unknown.
    public func rates(under band: ScoreBand) -> (falsePass: Double, falseFail: Double, unknown: Double) {
        let verdicts =
            (supported.map { (true, band.verdict(of: $0)) } + unsupported.map { (false, band.verdict(of: $0)) })
        let total = Double(max(1, verdicts.count))
        let wrong =
            Double(unsupported.filter { band.verdict(of: $0) == .pass }.count) / Double(max(1, unsupported.count))
        let missed = Double(supported.filter { band.verdict(of: $0) == .fail }.count) / Double(max(1, supported.count))
        return (wrong, missed, Double(verdicts.filter { $0.1 == .unknown }.count) / total)
    }

    private static func percentile(_ values: [Double], _ fraction: Double) -> Double {
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count) * fraction))]
    }
}

/// The decision rule of J1 §10, fixed before the run: a candidate stays for a language only when its AUROC is above the
/// control's and the low end of its 90% interval is above chance.
public enum GroundingDecision {
    public static func keeps(candidate: ScoredPairs, control: ScoredPairs) -> Bool {
        guard let area = candidate.auroc, let low = candidate.interval90?.lowerBound, let base = control.auroc else {
            return false
        }
        return area > base && low > 0.5
    }
}

/// Latency of one scorer, in milliseconds per pair after the first call.
public struct Latency: Sendable {
    public var milliseconds: [Double]

    public init(milliseconds: [Double]) { self.milliseconds = milliseconds }

    public var mean: Double { milliseconds.reduce(0, +) / Double(max(1, milliseconds.count)) }

    public func percentile(_ fraction: Double) -> Double {
        let sorted = milliseconds.sorted()
        return sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * fraction))]
    }
}
