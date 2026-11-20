import Foundation

extension Criteria {
    public func adding(_ rule: Rule) -> Criteria {
        var next = self
        next.rules.append(rule)
        return next
    }

    public func removing(_ id: String) -> Criteria {
        var next = self
        next.rules.removeAll { $0.id == id }
        return next
    }

    /// The criteria with one rule edited. When the edit changes what the model judges, the rule gets a new id, so the
    /// readings made for the old words are never taken as answers to the new ones.
    public func replacing(_ id: String, with edited: Rule) -> Criteria {
        guard let old = rule(id) else { return self }
        var rule = edited
        rule.id = old.needsNewReading(for: edited) ? Rule.newID() : old.id
        var next = self
        next.rules = rules.map { $0.id == id ? rule : $0 }
        return next
    }

    /// What the founder must fix before the criteria can be saved, in plain words; nil when they are sound.
    public var problem: String? {
        for rule in rules {
            switch rule.test {
            case .number(let number):
                if number.measure.cleaned == nil { return "A number rule needs a name for what it measures." }
                if number.comparison == .between, (number.high ?? number.low) < number.low {
                    return "\(number.measure.capitalizedFirst): the top of the range is below the bottom."
                }
            case .text(let text):
                if text.says.cleaned == nil { return "A want or don't-want rule needs words." }
            }
        }
        return nil
    }
}
