import CaptureService
import Foundation
import LocalSources
import TelegramReader
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
    let planUsage: PlanUsage
    let calls: CallNotes
    let callWatcher: CallWatcher
    let playback = CallPlayback()
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
            let store = try Store(directory: storeFolder)
            let service = try CaptureService(store: store)
            let identity = IdentityModel(store: store)
            try store.seedMachines(MachineTemplate.seeded.map { ($0.spec, $0.name) })
            let onboarding = OnboardingModel(store: store, identity: identity)
            let notifications = Notifications()
            let crew = Crew(
                store: store, capture: service, founder: { identity.identity.name }, makeModel: nil,
                notifications: notifications,
                telegram: TelegramAccount(
                    service: TDLibTelegram(folder: storeFolder.appending(path: "Telegram")), capture: service))
            let review = ReviewModel(store: store, crew: crew)
            let mochi = MochiModel(store: store, crew: crew)
            let catalog = TeamCatalogModel(store: store, crew: crew, author: { identity.identity.name })
            let deals = DealsModel(store: store, catalog: catalog)
            crew.onItemsChanged { deals.refresh() }
            let web = WebResearchSettings(store: store)
            let capture = CaptureSettings(service: service)
            let calls = CallNotes(
                store: store, listener: CallNotes.appleListener(), founder: { identity.identity.name },
                defaultPlace: storeFolder == defaultStoreFolder ? CallNotes.documentsPlace : nil,
                meetings: { interval in
                    try? await MeetingReader(calendar: EventKitCalendar(), policy: store)
                        .meetings(during: interval, at: .now)
                })
            capture.onCallSaved = { Task { await calls.processPending() } }
            let callWatcher = CallWatcher(
                store: store, controls: capture,
                announce: { title, body in
                    guard AlertStyle.current() != .popup else { return }
                    notifications.announce(title: title, body: body, page: .calls)
                })
            service.onListening = { callWatcher.update(listening: $0, playing: service.playingApps, at: .now) }
            let today = TodayModel(store: store, crew: crew, calendar: EventKitCalendar(), deals: { deals.deals })
            calls.onFollowUps = { today.refresh() }
            let session = AppSession(
                store: store, capture: capture, onboarding: onboarding, identity: identity,
                team: onboarding.teamModel, models: ModelSettings(store: store),
                crew: crew, review: review, mochi: mochi,
                today: today,
                reminders: Reminders(store: store, review: review, mochi: mochi, notifications: notifications),
                catalog: catalog, actions: ActionsModel(store: store, founder: { identity.identity.name }),
                deals: deals, memory: MemoryModel(store: store, crew: crew, deals: deals),
                web: web, claims: ClaimsModel(store: store, me: { catalog.me }, web: web),
                runs: RunsModel(store: store), planUsage: PlanUsage(store: store), calls: calls,
                callWatcher: callWatcher)
            service.start()
            Task { await calls.start() }
            session.reminders.start()
            return .ready(session)
        } catch {
            return .failed(StartupFailure(cause: error.localizedDescription, storeFolder: storeFolder))
        }
    }
}
