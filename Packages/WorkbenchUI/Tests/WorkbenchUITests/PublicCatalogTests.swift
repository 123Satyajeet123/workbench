import CaptureService
import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

@Suite struct PublicCatalogTests {
    private func mac(_ me: String, publicFolder: URL) throws -> (TeamCatalogModel, Crew, Store) {
        let store = try scratchStore()
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { me }, notifier: FakeNotifier())
        let catalog = TeamCatalogModel(store: store, crew: crew, author: { me })
        catalog.choosePublic(publicFolder)
        return (catalog, crew, store)
    }

    @Test func aPublishedMachineCountsAsReviewedOnlyByAnotherPersonAndOnlyForThatVersion() async throws {
        let folder = scratchFolder()
        let (aditya, adityasCrew, adityasStore) = try mac("Aditya", publicFolder: folder)
        let (kabir, _, _) = try mac("Kabir", publicFolder: folder)
        let id = try #require(adityasCrew.create(from: .dealIntake, name: "Deal intake"))
        let intake = try #require(adityasCrew.helper(id: id))
        let model = RecordedModel(ScriptedModel(#"{"items":[]}"#), store: adityasStore)
        let (_, run) = try await model.generate(
            Nothing.self, schema: .object([.init("items", .array(.string))]), task: intake.spec.task, instructions: "v",
            input: "x", holding: [])
        let day = WorkDay(containing: adityasStore.clock())
        let item = Item(
            task: intake.spec.task, day: day, scope: "", source: .mail, citeFirst: 1, citeLast: 1,
            start: day.start, end: day.start, fields: ["company": "Secret Co"], quote: "Secret Co raises", run: run)
        try adityasStore.saveReading(
            .init(items: [item], dropped: 0, run: run), of: intake.spec, day: day, scope: "",
            grant: CapturePolicy(switches: [.mail: true], allowList: [.mail: ["Deals"]])
                .authorize(CaptureRequest(kind: .mail, label: "Deals"), at: adityasStore.clock()).grant!)

        aditya.share(intake, to: .everyone)
        #expect(aditya.isShared(intake, in: .everyone) && !aditya.isShared(intake))
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        let text = try files.filter { $0.pathExtension == "json" }.map { try String(contentsOf: $0, encoding: .utf8) }
            .joined()
        #expect(text.contains("\"brief\"") && !text.contains("Secret Co"), "the spec goes, never what it read")

        kabir.refresh()
        let shared = try #require(kabir.publicMachines.first)
        #expect(kabir.approvers(of: shared, in: .everyone).isEmpty)
        aditya.refresh()
        aditya.review(try #require(aditya.published.first), in: .everyone, approve: true, note: "mine")
        kabir.review(shared, in: .everyone, approve: true, note: "Clear criteria.")
        kabir.refresh()
        #expect(kabir.approvers(of: shared, in: .everyone) == ["Kabir"], "an author cannot approve their own machine")

        adityasCrew.edit(intake, brief: "Rate by sector, stage and revenue.")
        aditya.share(intake, to: .everyone)
        kabir.refresh()
        let changed = try #require(kabir.publicMachines.first)
        #expect(kabir.approvers(of: changed, in: .everyone).isEmpty, "a new version needs a new review")
        #expect(kabir.myReview(of: changed, in: .everyone) == nil)
    }
}
