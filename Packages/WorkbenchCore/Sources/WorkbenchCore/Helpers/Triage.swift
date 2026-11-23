import Foundation

public enum Rating: String, Codable, Sendable, CaseIterable {
    case hot, warm, cold
}

public enum Verdict: String, Sendable, Codable, CaseIterable {
    case pass, fail
    /// The words gave no answer, or the model's quote was not in them. Never counted as a fail.
    case unknown
}

public struct RuleResult: Sendable, Equatable, Identifiable {
    public var rule: Rule
    public var verdict: Verdict
    public var number: Double?
    public var quote: String?
    public var reason: String?
    /// False when no reading answered this rule yet, such as a rule added after the deal was read.
    public var isRead: Bool

    public var id: String { rule.id }
}

public struct Triage: Sendable, Equatable {
    public var rating: Rating
    public var results: [RuleResult]
    /// The rules that decided the rating: the failed hard stops, or else the plus and minus that counted.
    public var decidedBy: [String]
    /// Why the investor should look at this deal, in words; empty when the call can stand.
    public var review: [String]

    public var needsReview: Bool { !review.isEmpty }

    /// The plus rules that pass, less the minus rules that fail: what orders deals inside one rating.
    public var points: Int {
        results.filter { $0.rule.role == .plus && $0.verdict == .pass }.count
            - results.filter { $0.rule.role == .minus && $0.verdict == .fail }.count
    }
}

extension Criteria {
    /// The rule that combines the results, in words the investor reads in the editor. `combine` follows it exactly.
    public var table: [String] {
        [
            "1. A deal-breaker fails: cold.",
            "2. A must fails: cold.",
            "3. Otherwise points = plus rules that pass, less minus rules that fail.",
            "4. Points of \(hotAt) or more: hot. 0 or more: warm. Fewer than 0: cold.",
            "5. A must or deal-breaker with no answer holds the deal at warm at most.",
            "An unknown never fails a rule. A missing number, an unclear rule or a conflict asks for your review.",
        ]
    }

    /// The overall call, from rule results only. The model judged each rule; this decides nothing else.
    public func combine(_ results: [RuleResult]) -> Triage {
        let failedBreakers = results.filter { $0.rule.role == .dealBreaker && $0.verdict == .fail }
        let failedMusts = results.filter { $0.rule.role == .must && $0.verdict == .fail }
        let plusPassed = results.filter { $0.rule.role == .plus && $0.verdict == .pass }
        let minusFailed = results.filter { $0.rule.role == .minus && $0.verdict == .fail }
        let hardStopUnknown = results.contains { $0.rule.role.isHardStop && $0.verdict == .unknown }
        let (rating, decided) = Self.rating(
            breakers: failedBreakers, musts: failedMusts, plus: plusPassed, minus: minusFailed,
            holdAtWarm: hardStopUnknown, hotAt: hotAt)
        let stopped = !failedBreakers.isEmpty || !failedMusts.isEmpty
        let conflict = !plusPassed.isEmpty && (stopped || !minusFailed.isEmpty)
        return Triage(
            rating: rating, results: results, decidedBy: decided.map(\.id),
            review: Self.review(results, conflict: conflict))
    }

    private static func rating(
        breakers: [RuleResult], musts: [RuleResult], plus: [RuleResult], minus: [RuleResult], holdAtWarm: Bool,
        hotAt: Int
    ) -> (Rating, [RuleResult]) {
        if !breakers.isEmpty { return (.cold, breakers) }
        if !musts.isEmpty { return (.cold, musts) }
        let points = plus.count - minus.count
        let rating: Rating = points >= hotAt ? .hot : points >= 0 ? .warm : .cold
        return (holdAtWarm && rating == .hot ? .warm : rating, plus + minus)
    }

    private static func review(_ results: [RuleResult], conflict: Bool) -> [String] {
        var reasons = results.compactMap { result -> String? in
            guard result.verdict == .unknown else { return nil }
            switch result.rule.test {
            case .number(let number): return "\(number.measure.capitalizedFirst) not found."
            case .text where result.rule.role.isHardStop: return "\(result.rule.summary) could not be judged."
            case .text: return nil
            }
        }
        if conflict { reasons.append("The rules point both ways.") }
        return reasons
    }
}
