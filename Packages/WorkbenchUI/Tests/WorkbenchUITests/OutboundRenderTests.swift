import Foundation
import SwiftUI
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// The Outbound page and a candidate's why card, drawn to PNGs for a person to look at. The folder comes from
/// `VC_PREVIEW_DIR`, else the temporary folder.
@MainActor
@Suite struct OutboundRenderTests {
    private func found() async throws -> OutboundWorld {
        let world = try OutboundWorld()
        try world.switchWeb(true)
        try await world.find()
        return world
    }

    @Test func theReviewListShowsRankedStartupsWithTheRunsQueriesAndCost() async throws {
        let world = try await found()
        let settings = WebResearchSettings(store: world.store, secrets: MemorySecrets())
        settings.refreshUsage()
        let catalog = TeamCatalogModel(store: world.store, crew: world.crew, author: { "Aditya" })
        let page = HelperContent(model: world.helper)
            .environment(ActionsModel(store: world.store, founder: { "Aditya" })).environment(world.crew)
            .environment(catalog).environment(world.fixture.deals).environment(settings)
            .environment(try captureSettings(over: world.store))
        try renderPNG(page, named: "outbound-review-list", width: 860)
    }

    @Test func aCandidatesWhyCardShowsEachRuleItsNumberItsQuoteAndTheLink() async throws {
        let world = try await found()
        let settings = WebResearchSettings(store: world.store, secrets: MemorySecrets())
        let cards = VStack(spacing: Space.m) {
            ForEach(Array(world.listed.prefix(2))) { candidate in
                CandidateCard(candidate: candidate, showsWhy: true, addToDeals: {}, notAFit: { _ in }, snooze: { _ in })
            }
        }
        .environment(settings)
        try renderPNG(cards, named: "outbound-why-card", width: 860)
    }
}
