import AppKit
import CaptureService
import Foundation
import SwiftUI
import WorkbenchCore

@testable import WorkbenchUI

/// A whole app session over a scratch store holding the sample day, with no capture running.
@MainActor
enum ShellFixture {
    static func session(
        template: TeamTemplate = .fund, extraMachines: [String] = [], finishedOnboarding: Bool = true
    ) async throws -> AppSession {
        let folder = scratchFolder()
        let writerLock = try StoreLock(directory: folder)
        let store = try Store(directory: folder)
        try store.seedMachines(MachineTemplate.seeded.map { ($0.spec, $0.name) })
        let service = try CaptureService(store: store)
        let identity = IdentityModel(store: store)
        identity.identity.name = "Kabir"
        let notifications = Notifications(notifier: FakeNotifier())
        let pages = try PageHostListener(path: PagesSocket.path(in: folder), store: store)
        let web = WebResearchSettings(store: store, browser: pages)
        let crew = Crew(
            store: store, capture: service, founder: { "Kabir" }, makeModel: nil, notifications: notifications,
            openWebSession: { try web.openSession() })
        for name in extraMachines { _ = crew.create(from: .team, name: name) }
        let onboarding = OnboardingModel(store: store, identity: identity, teamStarted: crew.reload)
        let review = ReviewModel(store: store, crew: crew)
        let mochi = MochiModel(store: store, crew: crew)
        let catalog = TeamCatalogModel(store: store, crew: crew, author: { identity.identity.name })
        let deals = DealsModel(store: store, catalog: catalog)
        try await TodaySample.populate(store: store, crew: crew, withSummaries: false)
        let session = AppSession(
            store: store, capture: CaptureSettings(service: service), onboarding: onboarding, identity: identity,
            team: onboarding.teamModel, models: ModelSettings(store: store), crew: crew, review: review, mochi: mochi,
            today: TodayModel(store: store, crew: crew, deals: { deals.deals }),
            reminders: Reminders(store: store, review: review, mochi: mochi, notifications: notifications),
            catalog: catalog, actions: ActionsModel(store: store, founder: { identity.identity.name }), deals: deals,
            memory: MemoryModel(store: store, crew: crew, deals: deals), web: web,
            claims: ClaimsModel(store: store, me: { catalog.me }, web: web), runs: RunsModel(store: store),
            pages: pages, writerLock: writerLock)
        session.team.template = template
        session.today.refresh()
        session.review.refresh()
        return session
    }
}
