import Foundation

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
    /// The name of the level the deal reached.
    public var rating: String
    /// The place of that level among the criteria's levels, 0 for the best.
    public var place: Int
    public var levelCount: Int
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
            "1. A deal-breaker fails: \(lowest?.name ?? "").",
            "2. A must fails: \(lowest?.name ?? "").",
            "3. Otherwise points = plus rules that pass, less minus rules that fail.",
            "4. \(levelSentence)",
            "5. A must or deal-breaker with no answer holds the deal at \(levels.dropFirst().first?.name ?? "") at most.",
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
        let (place, decided) = self.place(
            breakers: failedBreakers, musts: failedMusts, plus: plusPassed, minus: minusFailed,
            holdBelowBest: hardStopUnknown)
        let stopped = !failedBreakers.isEmpty || !failedMusts.isEmpty
        let conflict = !plusPassed.isEmpty && (stopped || !minusFailed.isEmpty)
        return Triage(
            rating: levels.indices.contains(place) ? levels[place].name : "", place: place, levelCount: levels.count,
            results: results, decidedBy: decided.map(\.id),
            review: Self.review(results, conflict: conflict))
    }

    private var levelSentence: String {
        let cuts = levels.dropLast().enumerated().map { index, level in
            "\(index == 0 ? "Points of " : "")\(level.cut ?? 0) or more: \(level.name)."
        }
        let rest = lowest.map { "Fewer than \(levels.dropLast().last?.cut ?? 0): \($0.name)." }
        return (cuts + [rest].compactMap { $0 }).joined(separator: " ")
    }

    private func place(
        breakers: [RuleResult], musts: [RuleResult], plus: [RuleResult], minus: [RuleResult], holdBelowBest: Bool
    ) -> (Int, [RuleResult]) {
        let last = max(levels.count - 1, 0)
        if !breakers.isEmpty { return (last, breakers) }
        if !musts.isEmpty { return (last, musts) }
        let place = place(forPoints: plus.count - minus.count)
        return (holdBelowBest ? min(max(place, 1), last) : place, plus + minus)
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
