import Foundation

/// The day's summaries of one machine's items, one per value of a field (a person or a project). Kept in the store and
/// written again only for a scope whose items changed: a new reading, a mark or a close.
public struct Summaries: Sendable {
    /// A scope with what a kept summary of it must match to stay current.
    private struct Group {
        var scope: SummaryScope
        var fingerprint: String
        var kinds: Set<SourceKind>

        var name: String { scope.name }

        func stored(_ summary: Summary) -> StoredSummary {
            StoredSummary(fingerprint: fingerprint, kinds: kinds, summary: summary)
        }
    }

    let store: Store
    let summarizer: Summarizer

    public init(store: Store, model: RecordedModel) {
        self.store = store
        summarizer = Summarizer(model: model)
    }

    /// The summaries of `day`, one per value of `field` among the items of machine `task`, in order of name: the kept
    /// ones, and one model call for all the scopes that have none or changed. Items marked wrong are left out; an item
    /// with no value in `field` belongs to no scope.
    public func summaries(for day: WorkDay, groupedBy field: String, of task: String) async throws -> [Summary] {
        guard let machine = try store.queries.machines().first(where: { $0.task == task }) else { return [] }
        let groups = try groups(of: machine, on: day, by: field)
        let kept = try store.queries.storedSummaries(day: day, task: task, field: field)
        let changed = Self.changed(groups, kept: kept)
        let written = Dictionary(
            uniqueKeysWithValues: try await summarizer.summarize(changed.map(\.scope), day: day).map { ($0.scope, $0) })
        let current = groups.compactMap { group -> StoredSummary? in
            if let summary = written[group.name] { return group.stored(summary) }
            return kept[group.name].flatMap { $0.fingerprint == group.fingerprint ? $0 : nil }
        }
        try store.saveSummaries(current, day: day, task: task, field: field)
        return current.map(\.summary)
    }

    /// Whether `summaries` would ask the model: some scope of `day` has no kept summary, or its items changed since.
    public func isMissing(for day: WorkDay, groupedBy field: String, of task: String) throws -> Bool {
        guard let machine = try store.queries.machines().first(where: { $0.task == task }) else { return false }
        let kept = try store.queries.storedSummaries(day: day, task: task, field: field)
        return !Self.changed(try groups(of: machine, on: day, by: field), kept: kept).isEmpty
    }

    private static func changed(_ groups: [Group], kept: [String: StoredSummary]) -> [Group] {
        groups.filter { kept[$0.name]?.fingerprint != $0.fingerprint }
    }

    /// Brings the day's summaries up to date after a reading, for the next time a page asks.
    public func refresh(for day: WorkDay, groupedBy field: String, of task: String) async throws {
        _ = try await summaries(for: day, groupedBy: field, of: task)
    }

    private func groups(of machine: Machine, on day: WorkDay, by field: String) throws -> [Group] {
        let items = try store.queries.items(of: machine.task, on: day).filter { $0.state != .rejected }
        let named = Dictionary(grouping: items.filter { !$0[field].isEmpty }, by: { $0[field] })
        let fields = machine.spec.fields.map(\.name)
        let version = try Digest.sha256(Summarizer.instructions + "\n" + Summarizer.schema.jsonText)
        return named.keys.sorted().map { value in
            let sources = named[value, default: []].map {
                CitedSource(machine: machine.name, fields: fields, item: $0)
            }
            let input = sources.compactMap(\.line).joined(separator: "\n")
            return Group(
                scope: SummaryScope(name: "\(field): \(value)", sources: sources),
                fingerprint: Digest.sha256(version + "\n" + input), kinds: Set(sources.map(\.item.source)))
        }
    }
}

extension HelperSpec {
    /// The first field that names a member (a person).
    public var memberField: String? {
        fields.first { if case .member = $0.kind { true } else { false } }?.name
    }

    /// The first field that names a label (a project).
    public var labelField: String? {
        fields.first { if case .label = $0.kind { true } else { false } }?.name
    }

    /// The fields a day's summaries group by: every field that names a member or a label (a person, a project), in the
    /// spec's order. None when the machine has neither.
    public var summaryFields: [String] {
        fields.compactMap { field in
            switch field.kind {
            case .member, .label: field.name
            case .text, .choice: nil
            }
        }
    }
}
