import Foundation

extension PageGate {
    /// The view that the words of a heading name, or nil. The words must be made of names the machine already has and
    /// nothing else, matched without regard to case: `by <field>`, `<value> by <field>`, `<value>`, `<form>`, or
    /// `<form> by <field>`, where a value may also be written in the plural. This matches structure against a closed
    /// set and reads no meaning; whatever it does not match is for the person's own request to the machine.
    /// The view keeps the heading as typed for its title, and everything the heading does not name.
    public func view(named heading: String, from view: FactsView, of spec: HelperSpec) -> FactsView? {
        let words = Self.normalized(heading)
        guard !words.isEmpty else { return nil }
        let countField = FirstForm.countField(of: spec)
        let named = Self.split(words)
        guard let found = resolve(named.head, field: named.field, from: view) else { return nil }
        var result = view
        if let form = found.form {
            result = result.changed(to: form, groupBy: found.field ?? view.groupBy, countField: countField) ?? result
        } else if let field = found.field {
            guard let grouped = result.changed(to: view.form, groupBy: field, countField: countField) else {
                return nil
            }
            result = grouped
        }
        if let value = found.value { result.filters[value.field] = [value.name] }
        result.title = heading.trimmingCharacters(in: .whitespacesAndNewlines)
        return allows(result) ? result : nil
    }

    private struct Found {
        var form: FactsView.Form?
        var field: String?
        var value: (field: String, name: String)?
    }

    private func resolve(_ head: String, field: String?, from view: FactsView) -> Found? {
        var found = Found()
        if let field {
            guard let name = catalog.values.keys.first(where: { Self.normalized($0) == field }) else { return nil }
            found.field = name
        }
        guard !head.isEmpty else { return found.field == nil ? nil : found }
        if let form = FactsView.Form.allCases.first(where: { Self.normalized(Self.words(of: $0)) == head }) {
            found.form = form
            return found
        }
        for (field, values) in catalog.values.sorted(by: { $0.key < $1.key }) {
            for value in values where [Self.normalized(value), Self.normalized(value) + "s"].contains(head) {
                found.value = (field, value)
                return found
            }
        }
        return nil
    }

    private static func words(of form: FactsView.Form) -> String {
        switch form {
        case .foldedList: "folded list"
        default: form.rawValue
        }
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// `<head> by <field>`, split at the last " by ", or the whole words as a head.
    private static func split(_ words: String) -> (head: String, field: String?) {
        if words.hasPrefix("by ") { return ("", String(words.dropFirst(3))) }
        guard let range = words.range(of: " by ", options: .backwards) else { return (words, nil) }
        return (String(words[..<range.lowerBound]), String(words[range.upperBound...]))
    }
}
