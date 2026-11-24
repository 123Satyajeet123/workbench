import Foundation

/// How rules reach the model and come back: one group of fields per rule in the reply, named by the rule id, kept in
/// the item's fields, and read again by code into rule results.
extension Rule {
    public var quoteKey: String { id + "_quote" }
    public var reasonKey: String { id + "_reason" }

    static let yes = "yes", no = "no", unclear = "unclear"

    /// The reply fields for this rule. Every property is required, so an answer with no words gives an empty string.
    var properties: [JSONSchema.Property] {
        switch test {
        case .number: [.init(id, .string), .init(quoteKey, .string)]
        case .text:
            [
                .init(id, .enumeration([Self.yes, Self.no, Self.unclear])), .init(quoteKey, .string),
                .init(reasonKey, .string),
            ]
        }
    }

    /// What the model is told to give for this rule. It never sees a limit, a role or a want against an avoid.
    var instruction: String {
        let quote = "exact words from the page text that show it, copied character for character, or empty"
        switch test {
        case .number(let number):
            let unit = number.unit.isEmpty ? "" : ", in \(number.unit)"
            return """
                - \(id) (number: \(number.measure)\(unit)): give `\(id)` as the number alone, no words or units, \
                or an empty string when the text gives none; never estimate. Give `\(quoteKey)`: \(quote).
                """
        case .text(let text):
            return """
                - \(id) (does the deal match: \(text.says)): give `\(id)` as yes, no or unclear. Give `\(quoteKey)`: \
                \(quote); empty when unclear. Give `\(reasonKey)`: one short English sentence.
                """
        }
    }
}

extension Criteria {
    /// The prompt block for the rules; empty when there are none.
    func instructions(for profile: WorkspaceProfile) -> String {
        guard !rules.isEmpty else { return "" }
        return """


            \(profile.render("{The occupation's}")) criteria. For each one give the fields named. You judge each rule; you do not rate the deal, \
            because code makes the call.
            \(rules.map(\.instruction).joined(separator: "\n"))
            Criteria version \(version).
            """
    }

    var properties: [JSONSchema.Property] { rules.flatMap(\.properties) }

    /// The fields to keep for one item of a reply. A rule whose answer is not a number, or whose quote is not in the
    /// page text, is kept as unknown with no quote: its result is never a guess. A rule the reply does not mention
    /// keeps nothing, so it reads as not yet read.
    func readings(_ raw: [String: JSONValue], evidence: EvidenceSet) -> [String: String] {
        var kept: [String: String] = [:]
        for rule in rules where raw[rule.id] != nil {
            let quote = raw[rule.quoteKey]?.string ?? ""
            let isQuoted = evidence.lines.contains { $0.contains(quote: quote) }
            let answer = raw[rule.id]?.string ?? ""
            switch rule.test {
            case .number:
                let isFound = isQuoted && Self.number(answer) != nil
                kept[rule.id] = isFound ? answer : ""
                kept[rule.quoteKey] = isFound ? quote : ""
            case .text:
                let isJudged = isQuoted && [Rule.yes, Rule.no].contains(answer)
                kept[rule.id] = isJudged ? answer : Rule.unclear
                kept[rule.quoteKey] = isJudged ? quote : ""
                kept[rule.reasonKey] = raw[rule.reasonKey]?.string?.cleaned ?? ""
            }
        }
        return kept
    }

    /// The fields of a reading that found nothing to judge: every rule read, none answered.
    var unanswered: [String: String] {
        readings(
            Dictionary(uniqueKeysWithValues: rules.map { ($0.id, JSONValue.string("")) }),
            evidence: EvidenceSet(lines: []))
    }

    /// A number as models write it: digits with a point, possibly with thousands commas. Nothing else counts.
    static func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces))
    }

    /// What each rule says about an item's kept fields, in the order of the rules.
    public func results(from fields: [String: String]) -> [RuleResult] {
        rules.map { rule in
            let answer = fields[rule.id]
            let quote = fields[rule.quoteKey]
            let reason = fields[rule.reasonKey]?.cleaned
            switch rule.test {
            case .number(let test):
                let value = answer.flatMap(Self.number)
                return RuleResult(
                    rule: rule, verdict: value.map { test.passes($0) ? .pass : .fail } ?? .unknown, number: value,
                    quote: quote, reason: nil, isRead: answer != nil)
            case .text(let test):
                let matches = answer.flatMap { [Rule.yes: true, Rule.no: false][$0] }
                let verdict: Verdict = matches.map { $0 == test.wants ? .pass : .fail } ?? .unknown
                return RuleResult(
                    rule: rule, verdict: verdict, number: nil, quote: quote, reason: reason, isRead: answer != nil)
            }
        }
    }

    public func triage(_ fields: [String: String]) -> Triage { combine(results(from: fields)) }
}
