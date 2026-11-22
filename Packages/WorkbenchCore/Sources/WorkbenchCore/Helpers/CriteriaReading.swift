import Foundation

extension Rule {
    public var quoteKey: String { id + "_quote" }
    public var reasonKey: String { id + "_reason" }

    static let yes = "yes", no = "no", unclear = "unclear"

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
    var instructions: String {
        guard !rules.isEmpty else { return "" }
        return """


            The investor's criteria. For each one give the fields named. You judge each rule; you do not rate the deal, \
            because code makes the call.
            \(rules.map(\.instruction).joined(separator: "\n"))
            Criteria version \(version).
            """
    }

    var properties: [JSONSchema.Property] { rules.flatMap(\.properties) }

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

    var unanswered: [String: String] {
        readings(
            Dictionary(uniqueKeysWithValues: rules.map { ($0.id, JSONValue.string("")) }),
            evidence: EvidenceSet(lines: []))
    }

    static func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces))
    }

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
