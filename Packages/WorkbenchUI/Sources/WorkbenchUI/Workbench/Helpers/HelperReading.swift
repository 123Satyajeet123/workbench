import Foundation
import Observation
import WorkbenchCore

/// Reads a day of the machine's source with the chosen model, and keeps where the last reading stopped so no line is
/// read twice.
@Observable
final class HelperReading {
    private(set) var phase = ReadPhase.idle

    @ObservationIgnored private let context: MachineContext

    init(context: MachineContext) { self.context = context }

    /// Shows no result of a reading, as when another day is shown.
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
            let full = try await context.source.evidence(on: day)
            // A reading starts where the last one stopped: earlier lines go along as context only, so nothing is
            // read twice and nothing comes back reworded.
            let lastLineKey = MachineKey.lastLine(spec.task, scope: scope, day: day)
            let last = try lastLineKey.load(from: store)
            var evidence = full.after(last)
            for (set, names) in try recentLabels() { evidence.context[set] = names }
            let open = try store.queries.openItems(readBy: spec, asOf: day == context.today ? nil : day)
            // A machine that follows another reads each day once even when nobody wrote, while there are facts to
            // watch: a commitment can fall due on a quiet day.
            let followedKey = MachineKey.followedRead(spec.task)
            let followsOpenFacts = spec.follows != nil && !open.isEmpty
            let isCaughtUp = followsOpenFacts ? try followedKey.load(from: store) == day : last != nil
            if evidence.newLines.isEmpty, isCaughtUp {
                phase = .upToDate
                context.problems.dismiss()
                return true
            }
            let model = context.makeModel(try context.runner(for: .init(spec)))
            let reader = HelperReader(spec: spec, model: model)
            let result = try await reader.read(
                day: day, scope: scope, evidence: evidence, marked: try context.marked(), open: open)
            try store.saveReading(
                result, of: spec, day: day, scope: scope, grant: try await context.grant(), replacing: last == nil)
            if let top = full.lines.map(\.id).max() { try lastLineKey.save(top, to: store) }
            if followsOpenFacts { try followedKey.save(day, to: store) }
            context.reloadIfShown(day)
            phase = .read(kept: result.items.count, dropped: result.dropped)
            context.problems.dismiss()
            context.itemsChanged()
            await refreshSummaries(day, model: model)
            return true
        } catch {
            phase = .idle
            context.problems.report("read the day", error)
            return false
        }
    }

    /// Brings the day's summaries up to date after a reading, one set for each field the machine groups by (people,
    /// projects), then tells the pages that read them. A failure here does not undo the reading.
    private func refreshSummaries(_ day: WorkDay, model: RecordedModel) async {
        let summaries = Summaries(store: context.store, model: model)
        for field in context.spec.summaryFields {
            do {
                try await summaries.refresh(for: day, groupedBy: field, of: context.spec.task)
            } catch {
                context.problems.report("summarize the day", error)
            }
        }
        context.itemsChanged()
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
