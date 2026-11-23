import CaptureService
import Foundation
import LocalSources
import TelegramReader
import WorkbenchCore

struct StartupFailure: Error, Equatable {
    let cause: String
    let storeFolder: URL
    let profile: Profile
}

struct AppSession {
    let profile: Profile
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
    let morning: MorningSchedule
    let catalog: TeamCatalogModel
    let actions: ActionsModel
    let deals: DealsModel
    let workspace: WorkspaceModel
    let memory: MemoryModel
    let web: WebResearchSettings
    let claims: ClaimsModel
    let runs: RunsModel
    /// Where the browser host sends what the extension read. Held so that it listens as long as the app runs.
    let pages: PageHostListener
    let browsers: BrowserSetup
    /// The right to write the store, held until the app ends.
    let writerLock: StoreLock
    let planUsage: PlanUsage
    let calls: CallNotes
    let callWatcher: CallWatcher
    let playback = CallPlayback()
    let navigation = Navigation()
}

enum AppLaunch {
    case ready(AppSession)
    case failed(StartupFailure)

    /// Opens the profile's store folder. A profile that refuses its folder never creates it.
    static func start(
        profile: Profile = .yours, storeFolder: URL? = nil, secrets: SecretStore = KeychainSecrets()
    ) -> AppLaunch {
        let folder = storeFolder ?? profile.defaultFolder
        if let refusal = profile.refusal(for: folder) {
            return .failed(StartupFailure(cause: refusal, storeFolder: folder, profile: profile))
        }
        return open(profile: profile, storeFolder: folder, secrets: secrets)
    }

    static func open(
        profile: Profile, storeFolder: URL, secrets: SecretStore, clock: @escaping @Sendable () -> Date = { Date() }
    ) -> AppLaunch {
        do {
            let writerLock = try StoreLock(directory: storeFolder)
            let store = try Store(directory: storeFolder, clock: clock)
            let owner = profile.owner(secrets: secrets)
            let service = try CaptureService(store: store, owner: owner)
            let capture = CaptureSettings(
                service: service, profile: profile, staleSites: { (try? store.queries.staleAdapters()) ?? [] },
                telegramKeysKnown: { TelegramAccount.keysSaved(in: secrets) })
            let identity = IdentityModel(store: store)
            let notifications = Notifications(notifier: profile.notifier, defaults: profile.notificationDefaults)
            let pages = try PageHostListener(path: PagesSocket.path(in: storeFolder), store: store, owner: owner)
            let web = WebResearchSettings(store: store, browser: pages)
            let crew = Crew(
                store: store, capture: service, founder: { identity.identity.name }, makeModel: nil,
                notifications: notifications, openWebSession: { try web.openSession() },
                whatsAppContainer: profile.whatsAppContainer(in: storeFolder),
                telegram: TelegramAccount(
                    service: TDLibTelegram(folder: store.directory.appending(path: "Telegram")), capture: service,
                    store: store, secrets: secrets))
            let onboarding = OnboardingModel(store: store, identity: identity, teamStarted: crew.reload)
            let review = ReviewModel(store: store, crew: crew)
            let mochi = MochiModel(store: store, crew: crew)
            let catalog = TeamCatalogModel(store: store, crew: crew, author: { identity.identity.name })
            let deals = DealsModel(store: store, catalog: catalog)
            crew.onItemsChanged { deals.refresh() }
            let today = TodayModel(
                store: store, crew: crew, calendar: profile.calendar, deals: { deals.deals },
                me: { identity.identity.name })
            let morning = MorningSchedule(
                store: store, notifications: notifications,
                needsCount: {
                    today.refresh()
                    return today.needsCount
                },
                notify: {
                    (try? await notifications.notifySummary(title: $0, body: "Open Today", page: .day)) == true
                })
            let calls = CallNotes(
                store: store, listener: CallNotes.appleListener(), founder: { identity.identity.name },
                owner: owner.get)
            capture.onCallSaved = { Task { await calls.processPending() } }
            let callWatcher = CallWatcher(
                store: store, controls: capture,
                announce: { notifications.announce(title: $0, body: $1, page: .calls) }, identify: service.source(of:))
            service.onListening = { callWatcher.update(listening: $0, at: .now) }
            let session = AppSession(
                profile: profile, store: store, capture: capture, onboarding: onboarding, identity: identity,
                team: onboarding.teamModel, models: ModelSettings(store: store, secrets: secrets),
                crew: crew, review: review, mochi: mochi,
                today: today,
                reminders: Reminders(store: store, review: review, mochi: mochi, notifications: notifications),
                morning: morning,
                catalog: catalog,
                actions: ActionsModel(
                    store: store, founder: { identity.identity.name }, reminders: profile.reminders),
                deals: deals, workspace: WorkspaceModel(store: store),
                memory: MemoryModel(store: store, crew: crew, deals: deals),
                web: web, claims: ClaimsModel(store: store, me: { catalog.me }, web: web, owner: owner),
                runs: RunsModel(store: store),
                pages: pages,
                browsers: BrowserSetup(
                    capture: capture, connectedBrowsers: { Set(pages.connectedBrowsers.map(\.browser)) }),
                writerLock: writerLock, planUsage: PlanUsage(store: store), calls: calls, callWatcher: callWatcher)
            if profile.startsCapture { service.start() }
            Task { await calls.start() }
            session.reminders.start()
            session.morning.start()
            return .ready(session)
        } catch {
            return .failed(
                StartupFailure(cause: error.localizedDescription, storeFolder: storeFolder, profile: profile))
        }
    }
}
