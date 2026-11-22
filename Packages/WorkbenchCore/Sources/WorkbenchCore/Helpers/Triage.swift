import Foundation

public enum Rating: String, Codable, Sendable, CaseIterable {
    case hot, warm, cold
}

public enum Verdict: String, Sendable {
    case pass, fail
    case unknown
}

public struct RuleResult: Sendable, Equatable, Identifiable {
    public var rule: Rule
    public var verdict: Verdict
    public var number: Double?
    public var quote: String?
    public var reason: String?
    public var isRead: Bool

    public var id: String { rule.id }
}

public struct Triage: Sendable, Equatable {
    public var rating: Rating
    public var results: [RuleResult]
    public var decidedBy: [String]
    public var review: [String]

    public var needsReview: Bool { !review.isEmpty }
}

extension Criteria {
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
