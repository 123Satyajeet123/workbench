import Foundation
import WorkbenchCore

/// The fields of the rule form, as the founder types them. `rule()` makes a rule only when the fields are sound.
struct RuleDraft: Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case number = "Number"
        case want = "Want"
        case avoid = "Don't want"

        var id: String { rawValue }
    }

    /// The rule being edited; nil for a new one.
    var editing: String?
    var kind = Kind.want
    var role = Rule.Role.plus
    var measure = ""
    var unit = ""
    var comparison = Comparison.atLeast
    var low = ""
    var high = ""
    var says = ""

    init() {}

    init(_ rule: Rule) {
        editing = rule.id
        role = rule.role
        switch rule.test {
        case .number(let number):
            kind = .number
            measure = number.measure
            unit = number.unit
            comparison = number.comparison
            low = number.low.shown
            high = number.high?.shown ?? ""
        case .text(let text):
            kind = text.wants ? .want : .avoid
            says = text.says
        }
    }

    func rule() -> Rule? {
        let test: Rule.Test
        switch kind {
        case .number:
            guard let measure = measure.cleaned, let low = Double(low.trimmed) else { return nil }
            let high = comparison == .between ? Double(high.trimmed) : nil
            guard comparison != .between || (high ?? -.infinity) >= low else { return nil }
            test = .number(
                NumberTest(measure: measure, unit: unit.trimmed, comparison: comparison, low: low, high: high))
        case .want, .avoid:
            guard let says = says.cleaned else { return nil }
            test = .text(TextTest(says: says, wants: kind == .want))
        }
        return Rule(id: editing ?? Rule.newID(), role: role, test: test)
    }
}

extension String {
    fileprivate var trimmed: String { trimmingCharacters(in: .whitespaces) }
}
