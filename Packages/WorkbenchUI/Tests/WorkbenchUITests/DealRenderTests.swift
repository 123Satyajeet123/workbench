import CaptureService
import SwiftUI
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// The deals board, a card with its ribbon and a deal's timeline drawn to PNGs for a person to look at. The folder
/// comes from `VC_PREVIEW_DIR`, else the temporary folder.
@Suite struct DealRenderTests {
    private func fixture() async throws -> (DealFixture, RunsModel, WorkObject) {
        let fixture = try DealFixture()
        let friday = try #require(WorkDay("2026-11-27"))
        let acme = try await fixture.deal("Acme Payroll", reading: VCFixture.hot, source: .whatsapp, mark: .confirmed)
        fixture.deals.claim(acme)
        fixture.deals.requireAction(
            try #require(fixture.deals.deal(acme.id)), what: "Get the cap table from the founder", due: friday)
        let bolt = try await fixture.deal("Bolt Pay", reading: VCFixture.missingNumber)
        fixture.deals.move(bolt, to: dealStage("In conversation"))
        let bet = try await fixture.deal("Bet Fantasy", reading: VCFixture.breaker, mark: .rejected)
        fixture.deals.move(bet, to: dealStage("Rejected"))
        fixture.deals.create(title: "Zeta Labs")
        return (fixture, RunsModel(store: fixture.store), try #require(fixture.deals.deal(acme.id)))
    }

    @Test func theBoardHasAColumnPerStageWithClassOwnerActionAndRibbonOnEachCard() async throws {
        let (fixture, runs, _) = try await fixture()
        let board = ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: Space.m) {
                ForEach(fixture.deals.columns) { StageColumn(column: $0, open: .constant(nil), move: { _, _ in }) }
            }
        }
        .environment(fixture.deals).environment(runs)
        try renderPNG(board.fixedSize(), named: "deals-board", width: 2200)
    }

    @Test func aCardShowsItsRibbon() async throws {
        let (fixture, runs, acme) = try await fixture()
        let card = DealCard(deal: acme, digest: fixture.deals.digests[acme.id]).frame(width: 220)
            .environment(fixture.deals).environment(runs)
        try renderPNG(card, named: "deals-card-ribbon", width: 300)
    }

    @Test func theDetailShowsTheStripTheRibbonAndTheTimeline() async throws {
        let (fixture, runs, acme) = try await fixture()
        let detail = DealDetail(deal: acme, move: { _, _ in }, close: {}).frame(width: 380)
            .environment(fixture.deals).environment(runs).environment(fixture.makeClaims())
        try renderPNG(detail.fixedSize(horizontal: false, vertical: true), named: "deals-detail-timeline", width: 420)
    }
}
