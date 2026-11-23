import Foundation

/// The rule a refused proposal broke. The raw value is what the store keeps.
public enum DropRule: String, CaseIterable, Sendable {
    /// A key is missing or has the wrong type.
    case malformed
    /// It cites a line that is not in the window, or that an earlier reading saw, or a range that runs backwards.
    case outsideWindow = "outside_window"
    /// Its quote is not in the lines it cites.
    case quoteNotInLines = "quote_not_in_lines"
    /// Its quote is shorter than the minimum, and is not the whole line.
    case quoteTooShort = "quote_too_short"
    /// A field value does not fit the kind of its field.
    case fieldKind = "field_kind"
    /// It names an open fact that the model was not shown.
    case unknownHandle = "unknown_handle"
    /// Its closing line is older than the fact it closes.
    case lineBeforeFact = "line_before_fact"
    /// An earlier proposal of the same reading says the same.
    case repeatInReading = "repeat_in_reading"
    /// A check failed with an error. A proposal that was not fully checked is never kept.
    case verifierError = "verifier_error"
}

/// A proposal the verifier refused: what the model wrote and the rule it broke.
public struct Drop: Sendable, Equatable {
    /// The list of the reply the proposal came from: "items", "closes" or "claims".
    public var part: String
    /// Its place in that list, from 0.
    public var ordinal: Int
    public var rule: DropRule
    /// As the model wrote it, in JSON.
    public var proposal: String

    public init(part: String, ordinal: Int, rule: DropRule, proposal: String) {
        self.part = part
        self.ordinal = ordinal
        self.rule = rule
        self.proposal = proposal
    }
}

/// What the verifier decided about one proposal.
public enum Judgment<Value: Sendable>: Sendable {
    case accepted(Value)
    case dropped(DropRule)
}

/// A check that refuses a proposal, with the rule it broke.
struct Refusal: Error {
    let rule: DropRule

    init(_ rule: DropRule) { self.rule = rule }
}
