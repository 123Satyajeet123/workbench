import Foundation

extension HelperSpec {
    /// Why this spec does not hold together, in plain words, or an empty list. The reader, the Verifier and the page
    /// name fields by string, so a name that no field has breaks them without a sound: this lists each such name.
    public var problems: [String] {
        let names = fields.map(\.name)
        var problems: [String] = []
        if brief.cleaned == nil { problems.append("the brief is empty") }
        if names.isEmpty { problems.append("the machine has no field") }
        if names.contains(where: { $0.cleaned == nil }) { problems.append("a field has no name") }
        problems += Set(names.filter { name in names.filter { $0 == name }.count > 1 }).sorted().map {
            "two fields are named \($0)"
        }
        if !names.contains(title) { problems.append("the title \(title) is not a field") }
        problems += badges.filter { !names.contains($0) }.map { "the badge \($0) is not a field" }
        problems += problemsOfTones + problemsOfView + (lifecycle?.problems(in: self) ?? [])
        if let nudge, !fields.contains(where: { $0.name == nudge.field && $0.kind == .member(of: nudge.expected) }) {
            problems.append("the nudge needs a member field \(nudge.field) of the set \(nudge.expected)")
        }
        return problems
    }

    /// Refuses a spec that has a problem. With `earlier`, only a problem that `earlier` did not have counts: a machine
    /// stored with a problem can still be changed in a way that does not make it worse.
    func requireCoherent(after earlier: HelperSpec? = nil) throws {
        let known = earlier?.problems ?? []
        let fresh = problems.filter { !known.contains($0) }
        if !fresh.isEmpty { throw HelperSpecError.incoherent(fresh) }
    }

    private var problemsOfTones: [String] {
        let values = Set(fields.flatMap { $0.kind.fixedValues ?? [] })
        return tones.keys.filter { !values.contains($0) }.sorted().map { "the tone of \($0) names no value of a field" }
    }

    private var problemsOfView: [String] {
        func named(_ field: String) -> HelperSpec.Field? { fields.first { $0.name == field } }
        switch view {
        case .table: return []
        case .timeline: return citation == .range ? [] : ["the timeline view needs facts that cite a run of lines"]
        case .board(let field, let expected):
            return named(field)?.kind == .member(of: expected) ? [] : ["the board view needs a member field \(field)"]
        case .grouped(let field):
            return named(field) == nil ? ["the view groups by \(field), which is not a field"] : []
        case .checklist(let field):
            return named(field) == nil || lifecycle == nil
                ? ["the checklist view needs a lifecycle and a field \(field)"] : []
        }
    }
}

extension HelperSpec.Lifecycle {
    fileprivate func problems(in spec: HelperSpec) -> [String] {
        var problems: [String] = []
        if let values = spec.fields.first(where: { $0.name == field })?.kind.fixedValues {
            problems += open.filter { !values.contains($0) }.map { "the open value \($0) is not a value of \(field)" }
        } else {
            problems.append("the lifecycle field \(field) is not a field with a fixed set of values")
        }
        if outcomes.isEmpty { problems.append("the lifecycle has no outcome") }
        problems += [owner, asker].compactMap { $0 }.filter { name in !spec.fields.contains { $0.name == name } }
            .map { "the lifecycle names \($0), which is not a field" }
        problems += (doneOutcomes ?? [:]).values.filter { !outcomes.contains($0) }.sorted().map {
            "the done outcome \($0) is not an outcome of the lifecycle"
        }
        return problems
    }
}

public enum HelperSpecError: Error, Equatable, LocalizedError {
    case noJob
    case incoherent([String])

    public var errorDescription: String? {
        switch self {
        case .noJob: "Write the job of the machine in one sentence."
        case .incoherent(let problems): "This design does not hold together: \(problems.joined(separator: "; "))."
        }
    }
}
