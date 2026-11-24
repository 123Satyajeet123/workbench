import SwiftUI

@testable import WorkbenchCore
@testable import WorkbenchUI

/// The pages the gates draw to PNGs for a person to look at.
@MainActor enum Renders {
    static func dealPage(_ deal: WorkObject, desk: Desk, png: URL) async throws {
        let team = TeamModel(store: desk.store, me: { "Aditya" })
        let page = DealDetail(deal: deal, move: { _, _ in }, close: {})
            .environment(desk.deals).environment(RunsModel(store: desk.store)).environment(desk.claims)
            .environment(desk.crew).environment(team).frame(width: 560, height: 1150)
        let file = try await renderPNG(page, named: "deal-page", in: png, width: 620)
        print("  png \(file.path)")
        let item = try require(
            desk.claims.state(of: deal).claims.compactMap { claim in
                claim.id.flatMap { desk.claims.state(of: deal).items[$0] }
            }.first)
        let proof = desk.claims.proofModel(crew: desk.crew)
        await proof.load(item)
        let inspector = InspectorView(item: item, surface: .deals) { EmptyView() }.environment(proof).environment(team)
            .frame(width: 380, height: 360)
        print("  png \(try await renderPNG(inspector, named: "claim-inspector", in: png, width: 420).path)")
    }

    static func firstLookPlan(onboarding: OnboardingModel, crew: Crew, png: URL, named name: String) async throws {
        let step = FirstLookStep().environment(onboarding).environment(crew).frame(height: 260)
        print("  png \(try await renderPNG(step, named: name, in: png, width: 560).path)")
    }

    static func firstLookResult(look: FirstLookModel, onboarding: OnboardingModel, png: URL, named name: String)
        async throws
    {
        let body = FirstLookBody(look: look).environment(onboarding).frame(height: 420)
        print("  png \(try await renderPNG(body, named: name, in: png, width: 560).path)")
    }

    static func watchlist(crew: Crew, png: URL) async throws {
        let step = WatchlistStep().environment(crew).frame(height: 300)
        print("  png \(try await renderPNG(step, named: "onboarding-watchlist", in: png, width: 600).path)")
    }
}
