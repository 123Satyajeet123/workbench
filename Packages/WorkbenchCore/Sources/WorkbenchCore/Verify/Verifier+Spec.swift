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
    /// their kinds, and an `objectRef` field names an object of its type that the model was shown. Its label and
    /// authority are computed here from what it cites.
    func item(
        _ raw: [String: JSONValue], spec: HelperSpec, open: [Item], objects: ObjectHandles = ObjectHandles(),
        day: WorkDay, scope: String, run: RunID
    ) throws -> Item {
        let cited = try cited(raw, spec: spec, day: day, open: open)
        var fields: [String: String] = [:]
        for field in spec.fields where !field.kind.isComputed {
            guard let given = raw[field.name] else { throw Refusal(.malformed) }
            if field.kind == .time {
                let mention = try time(given, citing: cited.lines)
                fields[field.name] = mention.words
                fields[Item.dueField] = try Coding.json(mention.due)
            } else if let type = field.kind.objectType {
                guard let handle = given.string else { throw Refusal(.malformed) }
                fields[field.name] = try Self.id(of: objects.resolve(handle, among: [type]))
            } else {
                guard let value = given.string else { throw Refusal(.malformed) }
                fields[field.name] = try Self.stored(value, fitsInto: field.kind, context: window.context)
            }
        }
        fields.merge(spec.criteria?.readings(raw, evidence: window) ?? [:]) { _, reading in reading }
        if !cited.facts.isEmpty {
            fields[Item.factsField] = Set(cited.facts.compactMap(\.id)).sorted().map(String.init).joined(separator: ",")
        }
        let standing = Standing(citing: cited.lines, facts: cited.facts, window: window.lines)
        return Item(
            task: spec.task, day: day, scope: scope, source: spec.source.consent, citeFirst: cited.first,
            citeLast: cited.last, start: cited.start, end: cited.end, fields: fields, quote: cited.quote, run: run,
            quoteSpan: cited.span, label: standing.label, authority: standing.authority)
    }

    /// The words of a time and the due time code worked out from its record.
    private struct Timed {
        var words: String
        var due: Due
    }

    /// A time field: a record that is exactly the closed record, whose parts agree, and whose words are in a cited line
    /// when there are any (and there are when the precision is not none). The due time is resolved against that line's
    /// own time, in the owner's zone.
    private func time(_ value: JSONValue, citing lines: [Evidence]) throws -> Timed {
        guard let mention = TimeMention(value), mention.record.isCoherent,
            mention.record.precision == .none || mention.words.cleaned != nil
        else { throw Refusal(.fieldKind) }
        guard let source = try lineHolding(mention.words, in: lines) else {
            return Timed(words: "", due: .unresolved(mention.record, zone: zone))
        }
        let hours = settings.dayHours ?? DayHours()
        return Timed(
            words: mention.words,
            due: TimeResolver.resolve(mention.record, anchor: source.start, zone: zone, hours: hours))
    }

    /// A proposal that passed its checks: the item it states, how it relates to the open facts, the due time it gives,
    /// and the home it names.
    struct Checked: Sendable {
        var item: Item
        var relation: Relation
        var due: Due?
        var home: ObjectHandles.Choice
    }

    /// The proposal of `spec`'s machine, whole: its item passes `item(_:spec:open:objects:day:scope:run:)`, and its
    /// relation passes `relation(_:spec:open:item:)`. Its home is read by `home(_:objects:)` and never refuses the
    /// proposal.
    func proposal(
        _ raw: [String: JSONValue], spec: HelperSpec, open: [Item], objects: ObjectHandles = ObjectHandles(),
        day: WorkDay, scope: String, run: RunID
    ) throws -> Checked {
        let item = try item(raw, spec: spec, open: open, objects: objects, day: day, scope: scope, run: run)
        return Checked(
            item: item, relation: try relation(raw, spec: spec, open: open, item: item), due: item.openedDue,
            home: home(raw, objects: objects))
    }

    /// The place a proposal files its item under. The model sees the places by handle, so a handle that names none of
    /// them is refused. An empty handle names none, and so does a reading that showed no places.
    func home(_ raw: [String: JSONValue], objects: ObjectHandles) -> ObjectHandles.Choice {
        guard objects.has(ObjectHandles.placeTypes), let handle = raw["object"]?.string else { return .none }
        return objects.resolve(handle, among: ObjectHandles.placeTypes)
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
            if let owner = lifecycle.owner, !sameOwner(item, target, field: owner, spec: spec) {
                throw Refusal(.identityMismatch)
            }
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

    /// The id of the object a handle of an `objectRef` field names, or empty for no object. A handle that names no
    /// object of the field's type refuses the proposal.
    private static func id(of choice: ObjectHandles.Choice) throws -> String {
        switch choice {
        case .none: ""
        case .object(let id): id
        case .refused: throw Refusal(.unknownHandle)
        }
    }

    /// Whether two items have the same owner: for a member field, the same member, however the stored value spells it.
    private func sameOwner(_ first: Item, _ second: Item, field: String, spec: HelperSpec) -> Bool {
        guard case .member(let set)? = spec.fields.first(where: { $0.name == field })?.kind else {
            return first[field] == second[field]
        }
        let roster = MemberRoster(set: set, in: window.context)
        return roster.canonical(first[field]) == roster.canonical(second[field])
    }

    /// The value to store for a field of `kind`, when the value fits it: a choice is one of its values, a member is
    /// in the context set (stored by its plain name), a date is a work day written yyyy-MM-dd, or empty when the field
    /// does not require one. Code sets a computed field, so a value for it never fits.
    private static func stored(_ value: String, fitsInto kind: HelperSpec.Field.Kind, context: [String: [String]])
        throws -> String
    {
        let fits: Bool
        switch kind {
        case .member(let set):
            guard let member = MemberRoster(set: set, in: context).member(for: value) else {
                throw Refusal(.fieldKind)
            }
            return member
        case .text(let required): fits = !required || value.cleaned != nil
        case .choice(let values): fits = values.contains(value)
        case .label: fits = value.cleaned != nil
        case .date(let required): fits = value.isEmpty ? !required : WorkDay(value) != nil
        case .computed, .time, .objectRef: fits = false
        }
        guard fits else { throw Refusal(.fieldKind) }
        return value
    }
}
