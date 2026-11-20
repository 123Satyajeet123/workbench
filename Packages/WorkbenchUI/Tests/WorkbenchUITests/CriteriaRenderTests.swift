import AppKit
import CaptureService
import Foundation
import SwiftUI
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// The why card, the criteria editor and the agreement report drawn to PNGs for a person to look at. The folder comes
/// from `VC_PREVIEW_DIR`, else the temporary folder.
@Suite struct CriteriaRenderTests {
    private func folder() -> URL {
        ProcessInfo.processInfo.environment["VC_PREVIEW_DIR"].map { URL(filePath: $0) }
            ?? FileManager.default.temporaryDirectory
    }

    private func write(_ view: some View, named name: String, width: CGFloat = 640) throws {
        let framed = view.padding(Space.l).frame(width: width, alignment: .topLeading)
            .background(Color(nsColor: .textBackgroundColor)).environment(\.colorScheme, .light)
        let host = NSHostingView(rootView: framed)
        host.frame = CGRect(origin: .zero, size: CGSize(width: width, height: host.fittingSize.height))
        let window = NSWindow(contentRect: host.frame, styleMask: [], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: folder().appending(path: "\(name).png"))
        #expect(png.count > 10_000)
    }

    private func triage(_ fields: [String: String]) -> Triage { VCFixture.thesis.triage(fields) }

    @Test func theWhyCardShowsEachRuleItsNumberAndItsWords() throws {
        let cards = VStack(alignment: .leading, spacing: Space.l) {
            Text("Hot: every rule answered").textStyle(.caption)
            WhyCard(triage: triage(VCFixture.hot))
            Text("Warm, with a missing number: needs your review").textStyle(.caption)
            WhyCard(triage: triage(VCFixture.missingNumber))
            Text("Cold: a deal-breaker matched").textStyle(.caption)
            WhyCard(triage: triage(VCFixture.breaker))
        }
        try write(cards, named: "why-card")
    }

    private func intake() async throws -> (HelperModel, Store) {
        let store = try scratchStore()
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "Aditya" }, notifier: FakeNotifier())
        var spec = HelperSpec.dealIntake
        spec.criteria = VCFixture.thesis
        let id = try #require(crew.create(spec: spec, template: "vc.deals", name: "Deal intake"))
        let helper = try #require(crew.helper(id: id))
        let readings = [VCFixture.hot, VCFixture.missingNumber, VCFixture.breaker]
        let model = RecordedModel(ScriptedModel("{}"), store: store)
        for (index, fields) in readings.enumerated() {
            let (_, run) = try await model.generate(
                [String: JSONValue].self, schema: .object([]), task: spec.task, instructions: "i", input: "x\(index)",
                holding: [.screenText])
            var named = fields
            named["company"] = ["Acme Payroll", "Bolt Pay", "Bet Fantasy"][index]
            let item = Item(
                task: helper.spec.task, day: helper.day, scope: "", source: .screenText, citeFirst: Int64(index),
                citeLast: Int64(index), start: helper.day.start, end: helper.day.start, fields: named,
                quote: "q\(index)",
                run: run)
            let policy = CapturePolicy(switches: [.screenText: true])
            try store.saveReading(
                HelperReader.Result(items: [item], dropped: 0, run: nil), of: helper.spec, day: helper.day,
                scope: "",
                grant: try #require(policy.authorize(CaptureRequest(kind: .screenText, label: nil), at: .now).grant),
                replacing: false)
        }
        return (helper, store)
    }

    @Test func theCriteriaEditorShowsRulesTheTableAndThePreviewOfAnUnsavedEdit() async throws {
        let (helper, _) = try await intake()
        let editor = CriteriaModel(helper: helper)
        var strict = try #require(editor.draft.rule("r_mrr"))
        strict.test = .number(.init(measure: "monthly revenue", unit: "USD", comparison: .atLeast, low: 50_000))
        editor.edit(strict)
        editor.commitForm()
        try write(CriteriaBody(model: editor, save: {}), named: "criteria-editor", width: 760)
        editor.add()
        editor.form?.kind = .number
        editor.form?.measure = "round size"
        editor.form?.unit = "USD"
        editor.form?.comparison = .between
        editor.form?.low = "500000"
        editor.form?.high = "3000000"
        try write(CriteriaBody(model: editor, save: {}), named: "criteria-editor-form", width: 760)
    }

    @Test func theAgreementReportShowsEveryNumberOnTheHeldOutSet() async throws {
        let (helper, store) = try await intake()
        let calls: [(String, Rating, [String: String])] = [
            ("Acme", .hot, VCFixture.hot), ("Bolt", .warm, VCFixture.missingNumber), ("Bet", .cold, VCFixture.breaker),
            ("Cyan", .hot, VCFixture.missingNumber), ("Dune", .cold, VCFixture.hot), ("Echo", .hot, VCFixture.breaker),
        ]
        for (company, call, reading) in calls {
            helper.agreement.add(company: company, text: "\(company) deck", url: "", call: call)
        }
        helper.agreement.add(company: "Fern", text: "Fern deck", url: "", call: .warm)
        try MachineKey.agreement(helper.spec.task).save(
            helper.agreement.deals.enumerated().map { index, deal in
                var read = deal
                read.reading = index < calls.count ? calls[index].2 : nil
                return read
            }, to: store)
        let again = HelperModel(
            machine: helper.machine, source: helper.source, store: store, makeModel: nil,
            notifier: FakeNotifier())
        try write(AgreementBody(agreement: again.agreement), named: "agreement-report", width: 760)
    }

}
