import Foundation
import Observation
import WorkbenchCore

/// Reads a day of the machine's source with the chosen model, and sends only the lines no earlier reading saw, so no
/// line is read twice.
@Observable
final class HelperReading {
    private(set) var phase = ReadPhase.idle

    @ObservationIgnored private let context: MachineContext

    init(context: MachineContext) { self.context = context }

    func forgetResult() { phase = .idle }

    /// The source must allow the read before the evidence is gathered and still allow it when the items are written.
    /// Returns whether the day was read or was already up to date.
    @discardableResult
    func read(_ day: WorkDay) async -> Bool {
        guard context.source.isReady, !context.isPaused, phase != .reading else { return false }
        phase = .reading
        let spec = context.spec
        let store = context.store
        let scope = context.source.scope
        do {
            _ = try await context.grant()
            if let counts = try await context.source.ownRead(spec: spec, model: makeModel) {
                context.reloadIfShown(day)
                phase = .read(kept: counts.kept, dropped: counts.dropped)
                context.problems.dismiss()
                context.itemsChanged()
                return true
            }
            var full = try await context.source.evidence(on: day)
            for (set, names) in try recentLabels() { full.context[set] = names }
            // A reading sends the lines no earlier reading saw: earlier lines go along as context only, so nothing is
            // read twice and nothing comes back reworded.
            let evidence = try store.queries.unread(full, by: spec.task)
            let asOf = day == context.today ? nil : day
            let openFacts = { try store.queries.openItems(readBy: spec, asOf: asOf) }
            let open = try openFacts()
            // A machine that follows another reads each day once even when nobody wrote, while there are facts to
            // watch: a commitment can fall due on a quiet day.
            let followedKey = MachineKey.followedRead(spec.task)
            let followsOpenFacts = spec.follows != nil && !open.isEmpty
            let isCaughtUp = followsOpenFacts ? try followedKey.load(from: store) == day : evidence.hasBeenRead
            if evidence.newLines.isEmpty, isCaughtUp {
                phase = .upToDate
                context.problems.dismiss()
                return true
            }
            let model = try makeModel()
            let reader = HelperReader(spec: spec, model: model, objects: try store.queries.objectsToShow(for: spec))
            let results = try await reader.readDay(
                day: day, scope: scope, evidence: evidence, marked: try context.marked(), open: openFacts,
                save: { result in
                    try store.saveReading(result, of: spec, day: day, scope: scope, grant: try await context.grant())
                })
            if followsOpenFacts { try followedKey.save(day, to: store) }
            context.reloadIfShown(day)
            phase = .read(kept: results.map(\.kept).reduce(0, +), dropped: results.map(\.dropped).reduce(0, +))
            context.problems.dismiss()
            context.itemsChanged()
            await refreshSummaries(day, with: Summaries(store: store, model: model))
            return true
        } catch {
            phase = .idle
            context.problems.report("read the day", error)
            return false
        }
    }

    /// The model the machine's spec reads with.
    private func makeModel() throws -> RecordedModel {
        context.makeModel(try context.runner(for: .init(context.spec)))
    }

    /// Whether the facts of `day` have summaries that are missing or out of date. Asks no model.
    func hasMissingSummaries(on day: WorkDay) -> Bool {
        guard let summaries = try? summaries() else { return false }
        return context.spec.summaryFields.contains {
            (try? summaries.isMissing(for: day, groupedBy: $0, of: context.spec.task)) ?? false
        }
    }

    /// Writes the summaries `day` lacks, as when a page opens on facts no reading summarized. Returns whether every
    /// set is current.
    func summarize(_ day: WorkDay) async -> Bool {
        do {
            return await refreshSummaries(day, with: try summaries())
        } catch {
            context.problems.report("summarize the day", error)
            return false
        }
    }

    private func summaries() throws -> Summaries {
        Summaries(store: context.store, model: try makeModel())
    }

    /// Brings the day's summaries up to date, one set for each field the machine groups by (people, projects), then
    /// tells the pages that read them. A failure here does not undo a reading.
    @discardableResult
    private func refreshSummaries(_ day: WorkDay, with summaries: Summaries) async -> Bool {
        var isCurrent = true
        for field in context.spec.summaryFields {
            do {
                try await summaries.refresh(for: day, groupedBy: field, of: context.spec.task)
            } catch {
                isCurrent = false
                context.problems.report("summarize the day", error)
            }
        }
        context.itemsChanged()
        return isCurrent
    }

    /// For each label field, the values this machine gave in the last 30 days, most used first, so a project keeps
    /// one name across days; the model may still start a new one.
    private func recentLabels() throws -> [String: [String]] {
        let spec = context.spec
        let fields = spec.fields.compactMap { field -> (name: String, set: String)? in
            if case .label(let set) = field.kind { (field.name, set) } else { nil }
        }
        guard !fields.isEmpty else { return [:] }
        let recent = try context.store.queries.items(of: spec.task, since: context.today.adding(days: -30))
            .filter { $0.state != .rejected }
        return Dictionary(
            fields.map { field in
                let counts = Dictionary(recent.map { ($0[field.name], 1) }, uniquingKeysWith: +)
                    .filter { !$0.key.isEmpty }
                return (field.set, counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(50).map(\.key))
            }, uniquingKeysWith: { first, _ in first })
    }
}
