import Foundation

/// The checks a machine's spec implies: its citation mode, its field kinds and its lifecycle. They are data of the
/// spec. No check reads a field's words.
extension Verifier {
    /// The span and words a kept item rests on, the lines and facts it cites, and the store ids of the facts.
    private struct Cited {
        var first: Int64
        var last: Int64
        var start: Date
        var end: Date
        var quote: String
        var span: QuoteSpan?
        var lines: [Evidence]
        var facts: [Item] = []
    }

    /// The item a proposal of `spec`'s machine states: its cited lines exist, its quote is in them, its fields fit
    /// their kinds. Its label and authority are computed here from what it cites.
    func item(
        _ raw: [String: JSONValue], spec: HelperSpec, open: [Item], day: WorkDay, scope: String, run: RunID
    ) throws -> Item {
        let cited = try cited(raw, spec: spec, day: day, open: open)
        var fields: [String: String] = [:]
        for field in spec.fields where !field.kind.isComputed {
            guard let value = raw[field.name]?.string else { throw Refusal(.malformed) }
            try Self.require(value, fitsInto: field.kind, context: window.context)
            fields[field.name] = value
        }
        fields.merge(spec.criteria?.readings(raw, evidence: window) ?? [:]) { _, reading in reading }
        if !cited.facts.isEmpty {
            fields[Item.factsField] = Set(cited.facts.compactMap(\.id)).sorted().map(String.init).joined(separator: ",")
        }
        let standing = Standing(citing: cited.lines, facts: cited.facts, window: window.lines)
        return Item(
            task: spec.task, day: day, scope: scope, source: spec.source.kind, citeFirst: cited.first,
            citeLast: cited.last, start: cited.start, end: cited.end, fields: fields, quote: cited.quote, run: run,
            quoteSpan: cited.span, label: standing.label, authority: standing.authority)
    }

    /// A proposal that passed its checks: the item it states, how it relates to the open facts, and the date it gives.
    struct Checked: Sendable {
        var item: Item
        var relation: Relation
        var due: String?
    }

    /// The proposal of `spec`'s machine, whole: its item passes `item(_:spec:open:day:scope:run:)`, and its relation
    /// passes `relation(_:spec:open:item:)`.
    func proposal(
        _ raw: [String: JSONValue], spec: HelperSpec, open: [Item], day: WorkDay, scope: String, run: RunID
    ) throws -> Checked {
        let item = try item(raw, spec: spec, open: open, day: day, scope: scope, run: run)
        return Checked(
            item: item, relation: try relation(raw, spec: spec, open: open, item: item),
            due: spec.lifecycle?.due.flatMap { raw[$0]?.string })
    }

    /// How a proposal relates to the open facts shown to the model. A machine with no lifecycle shows none, so every
    /// proposal is new. Else the model names one of five relations. Each handle must name an open fact of that
    /// reading. A `same_as` keeps the fact's owner. A `supersedes` or `closes` rests on a line not older than the fact
    /// it ends, and a `closes` names an outcome of the lifecycle.
    func relation(_ raw: [String: JSONValue], spec: HelperSpec, open: [Item], item: Item) throws -> Relation {
        guard let lifecycle = spec.lifecycle else { return .new }
        guard case .object(let given)? = raw["relation"], let kind = given["kind"]?.string,
            let handle = given["handle"]?.string, let outcome = given["outcome"]?.string
        else { throw Refusal(.malformed) }
        switch kind {
        case "new", "unsure":
            guard handle.isEmpty, outcome.isEmpty else { throw Refusal(.malformed) }
            return kind == "new" ? .new : .unsure
        case "same_as":
            guard outcome.isEmpty else { throw Refusal(.malformed) }
            let target = try fact(handle, open: open)
            if let owner = lifecycle.owner, item[owner] != target[owner] { throw Refusal(.identityMismatch) }
            return .sameAs(try id(of: target))
        case "supersedes":
            guard outcome.isEmpty else { throw Refusal(.malformed) }
            return .supersedes(try endedTarget(handle, by: item, open: open))
        case "closes":
            guard lifecycle.outcomes.contains(outcome) else { throw Refusal(.fieldKind) }
            return .closes(try endedTarget(handle, by: item, open: open), outcome: outcome)
        default: throw Refusal(.malformed)
        }
    }

    /// The open fact a proposal ends: its line is not older than the fact.
    private func endedTarget(_ handle: String, by item: Item, open: [Item]) throws -> Int64 {
        let target = try fact(handle, open: open)
        guard item.start >= target.start else { throw Refusal(.lineBeforeFact) }
        return try id(of: target)
    }

    private func id(of fact: Item) throws -> Int64 {
        guard let id = fact.id else { throw Refusal(.unknownHandle) }
        return id
    }

    private func cited(_ raw: [String: JSONValue], spec: HelperSpec, day: WorkDay, open: [Item]) throws -> Cited {
        switch spec.citation {
        case .one: try lines(raw["cite"]?.integer, raw["cite"]?.integer, raw: raw)
        case .range: try lines(raw["first"]?.integer, raw["last"]?.integer, raw: raw)
        case .facts: try facts(raw, day: day, open: open)
        }
    }

    private func lines(_ firstID: Int64?, _ lastID: Int64?, raw: [String: JSONValue]) throws -> Cited {
        guard let firstID, let lastID, let words = raw["quote"]?.string else { throw Refusal(.malformed) }
        guard firstID <= lastID, !window.isRead(firstID), let first = window.lines.first(where: { $0.id == firstID }),
            let last = window.lines.first(where: { $0.id == lastID })
        else { throw Refusal(.outsideWindow) }
        let between = window.lines.filter { (firstID...lastID).contains($0.id) }
        return Cited(
            first: firstID, last: lastID, start: first.start, end: last.end ?? last.start, quote: words,
            span: try quote(words, in: between), lines: between)
    }

    /// Every handle must name an open item and every line must exist and be new. The span runs over the cited lines;
    /// with none, it is 0 to 0 at the time of the latest line, or at the start of the day when it has no line.
    private func facts(_ raw: [String: JSONValue], day: WorkDay, open: [Item]) throws -> Cited {
        guard let handles = raw["facts"]?.array, !handles.isEmpty, let given = raw["lines"]?.array,
            let words = raw["quote"]?.string
        else { throw Refusal(.malformed) }
        let ids = given.compactMap(\.integer)
        guard ids.count == given.count else { throw Refusal(.malformed) }
        let facts = try handles.map { try fact($0.string ?? "", open: open) }
        let lines = try ids.map(newLine)
        let latest = window.lines.map(\.start).max() ?? day.start
        return Cited(
            first: ids.min() ?? 0, last: ids.max() ?? 0, start: lines.map(\.start).min() ?? latest,
            end: lines.map { $0.end ?? $0.start }.max() ?? latest, quote: words,
            span: try quote(words, in: lines, orIn: facts), lines: lines, facts: facts)
    }

    /// The open item a handle such as "F2" names.
    private func fact(_ handle: String, open: [Item]) throws -> Item {
        guard handle.first == "F", let index = Int(handle.dropFirst()), open.indices.contains(index - 1),
            open[index - 1].id != nil
        else { throw Refusal(.unknownHandle) }
        return open[index - 1]
    }

    /// A value fits its field when it is of the field's kind: a choice is one of its values, a member is in the
    /// context set, a date is a work day written yyyy-MM-dd, or empty when the field does not require one. Code sets a
    /// computed field, so a value for it never fits.
    private static func require(_ value: String, fitsInto kind: HelperSpec.Field.Kind, context: [String: [String]])
        throws
    {
        let fits =
            switch kind {
            case .text(let required): !required || value.cleaned != nil
            case .choice(let values): values.contains(value)
            case .member(let set): context[set]?.contains(value) == true
            case .label: value.cleaned != nil
            case .date(let required): value.isEmpty ? !required : WorkDay(value) != nil
            case .computed: false
            }
        guard fits else { throw Refusal(.fieldKind) }
    }
}
