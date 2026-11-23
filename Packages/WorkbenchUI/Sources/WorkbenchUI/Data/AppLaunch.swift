import CaptureService
import Foundation
import LocalSources
import WorkbenchCore

struct StartupFailure: Error, Equatable {
    let cause: String
    let storeFolder: URL
}

struct AppSession {
    let store: Store
    let capture: CaptureSettings
    let onboarding: OnboardingModel
    let identity: IdentityModel
    let team: TeamModel
    let models: ModelSettings
    let crew: Crew
    let review: ReviewModel
    let mochi: MochiModel
    let today: TodayModel
    let reminders: Reminders
    let catalog: TeamCatalogModel
    let actions: ActionsModel
    let deals: DealsModel
    let memory: MemoryModel
    let web: WebResearchSettings
    let claims: ClaimsModel
    let runs: RunsModel
    /// Where the browser host sends what the extension read. Held so that it listens as long as the app runs.
    let pages: PageHostListener
    /// The right to write the store, held until the app ends.
    let writerLock: StoreLock
    let navigation = Navigation()
}

enum AppLaunch {
    case ready(AppSession)
    case failed(StartupFailure)

    static var defaultStoreFolder: URL {
        URL.applicationSupportDirectory.appending(path: "Workbench")
    }

    static func start(storeFolder: URL = defaultStoreFolder) -> AppLaunch {
        do {
            let writerLock = try StoreLock(directory: storeFolder)
            let store = try Store(directory: storeFolder)
            let owner = OwnerIdentity.result(secrets: KeychainSecrets())
            let service = try CaptureService(store: store, owner: owner)
            let identity = IdentityModel(store: store)
            let notifications = Notifications()
            let pages = try PageHostListener(path: PagesSocket.path(in: storeFolder), store: store, owner: owner)
            let web = WebResearchSettings(store: store, browser: pages)
            let crew = Crew(
                store: store, capture: service, founder: { identity.identity.name }, makeModel: nil,
                notifications: notifications, openWebSession: { try web.openSession() })
            let onboarding = OnboardingModel(store: store, identity: identity, teamStarted: crew.reload)
            let review = ReviewModel(store: store, crew: crew)
            let mochi = MochiModel(store: store, crew: crew)
            let catalog = TeamCatalogModel(store: store, crew: crew, author: { identity.identity.name })
            let deals = DealsModel(store: store, catalog: catalog)
            crew.onItemsChanged { deals.refresh() }
            let session = AppSession(
                store: store, capture: CaptureSettings(service: service), onboarding: onboarding, identity: identity,
                team: onboarding.teamModel, models: ModelSettings(store: store),
                crew: crew, review: review, mochi: mochi,
                today: TodayModel(store: store, crew: crew, calendar: EventKitCalendar(), deals: { deals.deals }),
                reminders: Reminders(store: store, review: review, mochi: mochi, notifications: notifications),
                catalog: catalog, actions: ActionsModel(store: store, founder: { identity.identity.name }),
                deals: deals, memory: MemoryModel(store: store, crew: crew, deals: deals),
                web: web, claims: ClaimsModel(store: store, me: { catalog.me }, web: web),
                runs: RunsModel(store: store),
                pages: pages,
                writerLock: writerLock)
            service.start()
            session.reminders.start()
            return .ready(session)
        } catch {
            return .failed(StartupFailure(cause: error.localizedDescription, storeFolder: storeFolder))
        }
    }
}
