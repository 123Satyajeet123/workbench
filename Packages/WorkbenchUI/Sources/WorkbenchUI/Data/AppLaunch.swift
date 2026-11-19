import CaptureService
import Foundation
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
    let runs: RunsModel
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
            try store.seedMachines(MachineTemplate.all.map { ($0.spec, $0.name) })
            let onboarding = OnboardingModel(store: store, identity: identity)
            let session = AppSession(
                store: store, capture: CaptureSettings(service: service), onboarding: onboarding, identity: identity,
                team: onboarding.teamModel, models: ModelSettings(store: store),
                crew: Crew(store: store, capture: service, founder: { identity.identity.name }),
                runs: RunsModel(store: store))
            service.start()
            return .ready(session)
        } catch {
            return .failed(StartupFailure(cause: error.localizedDescription, storeFolder: storeFolder))
        }
    }
}
