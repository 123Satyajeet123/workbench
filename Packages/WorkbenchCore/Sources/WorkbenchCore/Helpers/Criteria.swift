import Foundation

/// The investor's thesis as data: rules the model judges one by one, and the line a deal needs to be hot. Code makes
/// the overall call from the rule results (`Triage`); the model never does.
public struct Criteria: Codable, Sendable, Equatable {
    public var rules: [Rule]
    public var hotAt: Int

    public init(rules: [Rule] = [], hotAt: Int = 1) {
        self.rules = rules
        self.hotAt = hotAt
    }

    /// A short fingerprint of every rule, role and limit. It is part of the instructions, so any edit to the criteria
    /// is a new prompt version that earns trust again, as an edit of the brief is.
    public var version: String {
        let text = (try? Coding.json(self)) ?? ""
        return String(Digest.sha256(text).prefix(8))
    }

    public func rule(_ id: String) -> Rule? { rules.first { $0.id == id } }
}

public struct Rule: Codable, Sendable, Equatable, Identifiable {
    /// What a rule does to the call. Must and deal-breaker act when the rule fails; plus when it passes; minus when
    /// it fails.
    public enum Role: String, Codable, Sendable, CaseIterable {
        case must, plus, minus
        case dealBreaker = "deal_breaker"

        public var isHardStop: Bool { self == .must || self == .dealBreaker }

        public var words: String {
            switch self {
            case .must: "must"
            case .plus: "plus"
            case .minus: "minus"
            case .dealBreaker: "deal-breaker"
            }
        }
    }

    public enum Test: Codable, Sendable, Equatable {
        /// The model finds a number and its quote; code compares it.
        case number(NumberTest)
        /// The model judges whether the deal matches the words; code reads the answer by the rule's polarity.
        case text(TextTest)
    }

    public var id: String
    public var role: Role
    public var test: Test

    public init(id: String = Rule.newID(), role: Role, test: Test) {
        self.id = id
        self.role = role
        self.test = test
    }

    /// A rule id never reused, so a judgment made for an earlier rule cannot be read as this one's.
    public static func newID() -> String { "r_" + UUID().uuidString.prefix(6).lowercased() }

    public var summary: String {
        switch test {
        case .number(let number): number.summary
        case .text(let text): (text.wants ? "Wants: " : "Avoids: ") + text.says
        }
    }

    /// What the model is asked about: when this changes, earlier judgments no longer answer it.
    var judged: String {
        switch test {
        case .number(let number): "number|\(number.measure)|\(number.unit)"
        case .text(let text): "text|\(text.says)"
        }
    }

    /// Whether the model must read again for `edited` to be answered: only a change of what it judges needs it. A
    /// limit, a role or a want turned to an avoid is applied by code to the judgment already made.
    public func needsNewReading(for edited: Rule) -> Bool { judged != edited.judged }
}

public enum Comparison: String, Codable, Sendable, CaseIterable {
    case above, atLeast, below, atMost, between

    public var words: String {
        switch self {
        case .above: "above"
        case .atLeast: "at least"
        case .below: "below"
        case .atMost: "at most"
        case .between: "between"
        }
    }
}

/// A rule on a number, such as employee count above 20. `high` is used by `between` only.
public struct NumberTest: Codable, Sendable, Equatable {
    public var measure: String
    public var unit: String
    public var comparison: Comparison
    public var low: Double
    public var high: Double?

    public init(measure: String, unit: String, comparison: Comparison, low: Double, high: Double? = nil) {
        self.measure = measure
        self.unit = unit
        self.comparison = comparison
        self.low = low
        self.high = high
    }

    public func passes(_ value: Double) -> Bool {
        switch comparison {
        case .above: value > low
        case .atLeast: value >= low
        case .below: value < low
        case .atMost: value <= low
        case .between: value >= low && value <= (high ?? low)
        }
    }

    public var summary: String {
        let limit = comparison == .between ? "\(low.shown) and \((high ?? low).shown)" : low.shown
        return "\(measure.capitalizedFirst) \(comparison.words) \(limit) \(unit)".trimmingCharacters(in: .whitespaces)
    }
}

public struct TextTest: Codable, Sendable, Equatable {
    public var says: String
    /// True when a match is good (a want); false when a match is bad (an avoid).
    public var wants: Bool

    public init(says: String, wants: Bool) {
        self.says = says
        self.wants = wants
    }
}

extension Double {
    public var shown: String { rounded() == self ? String(Int(self)) : String(self) }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
