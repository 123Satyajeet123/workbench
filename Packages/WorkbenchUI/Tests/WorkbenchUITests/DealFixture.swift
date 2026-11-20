import CaptureService
import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// A founder with a deal-intake machine that rates by `VCFixture.thesis`, Pip, Sentinel and a deals model, all over
/// one scratch store. Items are saved as a reading would save them; no model is called.
@MainActor
final class DealFixture {
    let store: Store
    let crew: Crew
    let deals: DealsModel
    let intake: HelperModel
    let sentinel: Machine

    init() throws {
        store = try scratchStore()
        try store.seedMachines(MachineTemplate.seeded.map { ($0.spec, $0.name) })
        crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "Aditya" }, notifier: FakeNotifier())
        deals = DealsModel(store: store, catalog: TeamCatalogModel(store: store, crew: crew, author: { "Aditya" }))
        var spec = HelperSpec.dealIntake
        spec.criteria = VCFixture.thesis
        let machine = try store.createMachine(from: spec, template: "vc.deals", name: "Deal intake")
        intake = HelperModel(
            machine: machine, source: try PageSource(store: store, task: machine.task), store: store,
            makeModel: { [store] _ in RecordedModel(ScriptedModel("{}"), store: store) }, notifier: FakeNotifier())
        var watch = HelperSpec.derailment
        watch.follows = try #require(try store.queries.machines().first { $0.template == HelperSpec.team.task }).task
        sentinel = try store.createMachine(from: watch, template: HelperSpec.derailment.task, name: "Sentinel")
    }

    /// A deal made from an intake item the criteria rate from `reading`, captured from `source`.
    @discardableResult
    func deal(
        _ company: String, reading: [String: String], source: SourceKind = .screenText, mark: Mark? = nil
    ) async throws -> WorkObject {
        let model = RecordedModel(ScriptedModel("{}"), store: store)
        let (_, run) = try await model.generate(
            [String: JSONValue].self, schema: .object([]), task: intake.spec.task, instructions: "i",
            input: company, holding: [.screenText])
        var fields = reading
        fields["company"] = company
        let item = Item(
            task: intake.spec.task, day: intake.day, scope: "", source: source, citeFirst: 1, citeLast: 1,
            start: intake.day.start, end: intake.day.start, fields: fields, quote: "\(company) is raising", run: run)
        let policy = CapturePolicy(switches: [.screenText: true])
        try store.saveReading(
            HelperReader.Result(items: [item], dropped: 0, run: nil), of: intake.spec, day: intake.day, scope: "",
            grant: try #require(policy.authorize(CaptureRequest(kind: .screenText, label: nil), at: .now).grant),
            replacing: false)
        let saved = try #require(try store.queries.items(of: intake.spec.task, on: intake.day).last)
        if let mark { try store.mark(item: try #require(saved.id), as: mark) }
        let id = try #require(await deals.newDeal(from: saved, of: intake))
        return try #require(deals.deal(id))
    }
}
