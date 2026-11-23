import Foundation
import Observation
import WorkbenchCore

/// Asking the team's memory: the founder's machines' items and the deals' notes and items they may read.
@Observable
final class MemoryModel {
    static let days = 90

    private(set) var answer: Asker.Answer?
    private(set) var asking = false
    private(set) var problem: String?

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let crew: Crew
    @ObservationIgnored private let deals: DealsModel
    @ObservationIgnored private let makeModel: (ModelChoice) -> RecordedModel

    init(store: Store, crew: Crew, deals: DealsModel, makeModel: ((ModelChoice) -> RecordedModel)? = nil) {
        self.store = store
        self.crew = crew
        self.deals = deals
        self.makeModel = makeModel ?? { $0.model(store: store) }
    }

    /// Everything the founder may ask about. Items they marked wrong are left out.
    func entries() throws -> [MemoryEntry] {
        let since = WorkDay(containing: store.clock()).adding(days: -Self.days)
        var entries: [MemoryEntry] = []
        for machine in crew.machines {
            for item in try store.queries.items(of: machine.spec.task, since: since) where item.state != .rejected {
                guard let id = item.id else { continue }
                let values = machine.spec.fields.map { item[$0.name] }.filter { !$0.isEmpty }
                entries.append(
                    MemoryEntry(
                        id: "item:\(id)", source: "\(machine.name) · \(item.day)",
                        text: (values + [item.quote]).joined(separator: " — "), quote: item.quote,
                        kinds: [item.source]))
            }
        }
        for deal in deals.deals {
            for note in deal.notes {
                entries.append(
                    MemoryEntry(
                        id: "note:\(note.id)", source: "\(deal.title) · note by \(note.author)",
                        text: "\(deal.title): \(note.text)", quote: note.text))
            }
            for linked in deal.items where linked.item.state != .rejected {
                let values = linked.item.columns.compactMap { linked.item.fields[$0] }.filter { !$0.isEmpty }
                entries.append(
                    MemoryEntry(
                        id: "link:\(linked.event.id)", source: "\(deal.title) · \(linked.item.machine)",
                        text: ([deal.title] + values + [linked.item.quote]).joined(separator: " — "),
                        quote: linked.item.quote, kinds: linked.item.source.map { [$0] } ?? [],
                        kindUnknown: linked.item.source == nil))
            }
        }
        return entries
    }

    func ask(_ question: String) async {
        guard let question = question.cleaned, !asking else { return }
        asking = true
        defer { asking = false }
        do {
            let asker = Asker(model: makeModel(try ModelChoice.saved(in: store)))
            answer = try await asker.ask(question, entries: try entries()).answer
            problem = nil
        } catch Asker.Refusal.badCitation {
            answer = nil
            problem = "The answer cited something it was not given, so it is not shown."
        } catch {
            answer = nil
            problem = "Could not ask: \(error.localizedDescription)"
        }
    }

    func clear() {
        answer = nil
        problem = nil
    }
}
