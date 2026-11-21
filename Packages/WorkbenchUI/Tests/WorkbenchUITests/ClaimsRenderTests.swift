import SwiftUI
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// A deal's claim verdicts and the web research section of Settings, drawn to PNGs. The folder comes from
/// `VC_PREVIEW_DIR`, else the temporary folder.
@MainActor
@Suite struct ClaimsRenderTests {
    private func dealWithVerdicts() async throws -> (DealFixture, WorkObject, ClaimsModel) {
        let fixture = try DealFixture()
        let deal = try await fixture.deal("Acme Payroll", reading: VCFixture.hot, source: .whatsapp, mark: .confirmed)
        let store = fixture.store
        try store.savePolicy(CapturePolicy(switches: [.web: true, .mail: true], allowList: [.mail: ["Deals"]]))
        let search = RecordingSearch()
        let session = try WebSession.open(store: store, key: { _ in "k" }, make: { _, _, _ in (search, search) })
        let (_, run) = try await RecordedModel(ScriptedModel("{}"), store: store).generate(
            [String: JSONValue].self, schema: .object([]), task: "claims.extract", instructions: "i", input: "deck",
            holding: [.mail])
        let rows: [(String, ClaimType, String, ClaimVerdict, String, String)] = [
            (
                "Acme raised a $20 million seed round in 2023.", .funding, "$20 million", .contradicted,
                "has raised $11 Mn in its seed funding round", "https://inc42.com/buzz/acme-seed"
            ),
            (
                "Acme was founded in 2022.", .teamBackground, "2022", .supported, "founded in 2022 by three founders",
                "https://entrackr.com/acme"
            ),
            ("Acme serves 40 banks.", .customers, "40 banks", .notFound, "", ""),
            ("The Indian payroll market is $5 billion.", .marketSize, "$5 billion", .unclear, "", ""),
        ]
        let ids = try store.saveClaims(
            rows.map { Claim(deal: deal.id, text: $0.0, type: $0.1, value: $0.2, quote: $0.0, line: 1) }, run: run,
            grant: try #require(
                CapturePolicy(switches: [.mail: true], allowList: [.mail: ["Deals"]]).authorize(
                    CaptureRequest(kind: .mail, label: "Deals"), at: .now
                ).grant))
        try store.choose(claims: Array(ids.prefix(3)), deal: deal.id)
        for (id, row) in zip(ids, rows) {
            let check = ClaimCheck(
                claim: id, deal: deal.id, claimText: row.0, verdict: row.3, quote: row.4, url: row.5, checkedAt: .now)
            let item = try store.saveCheck(check, claimQuote: row.0, run: run, session: session)
            if row.3 == .contradicted {
                try store.mark(item: item, as: .confirmed)
                try store.markQuote(of: item, as: .confirmed)
            }
        }
        let claims = fixture.makeClaims()
        claims.refresh(deal)
        return (fixture, deal, claims)
    }

    @Test func aDealShowsEachVerdictWithItsQuoteLinkAndTwoMarks() async throws {
        let (_, deal, claims) = try await dealWithVerdicts()
        let section = ClaimChecksSection(deal: deal).environment(claims).frame(width: 420)
        try renderPNG(section.fixedSize(horizontal: false, vertical: true), named: "deal-claim-verdicts", width: 460)
        #expect(claims.state(of: deal).checks.map(\.verdict) == [.contradicted, .supported, .notFound, .unclear])
    }

    @Test func settingsShowTheWebResearchSectionOffThenOnWithProviderKeyAndCap() throws {
        let store = try scratchStore()
        let capture = try captureSettings(over: store)
        let web = WebResearchSettings(store: store, secrets: MemorySecrets())
        let off = Form { WebResearchSection() }.formStyle(.grouped).environment(capture).environment(web)
        try renderPNG(off.frame(height: 200), named: "settings-web-research-off", width: 560)
        capture.set(.web, on: true)
        web.saveKey("brave-key")
        let on = Form { WebResearchSection() }.formStyle(.grouped).environment(capture).environment(web)
        try renderPNG(on.frame(height: 360), named: "settings-web-research-on", width: 560)
        #expect(capture.isOn(.web))
    }
}
