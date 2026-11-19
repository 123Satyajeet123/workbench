import Foundation
import Observation
import WorkbenchCore

@Observable
final class OnboardingModel {
    let screens = OnboardingScreen.allCases
    let identityModel: IdentityModel
    let teamModel: TeamModel
    private(set) var index = 0 { didSet { save() } }
    private(set) var isFinished = false { didSet { save() } }
    private(set) var saveError: (any Error)?
    @ObservationIgnored private let store: Store?

    private struct Saved: Codable {
        var index: Int
        var isFinished: Bool
    }

    private static let stateKey = StateKey<Saved>.json("onboarding")

    init(store: Store? = nil, identity: IdentityModel = IdentityModel(), team: TeamModel? = nil) {
        self.store = store
        identityModel = identity
        teamModel = team ?? TeamModel(store: store, me: { identity.identity.name })
        do {
            guard let saved = try Self.savedState(in: store) else { return }
            index = saved.index
            isFinished = saved.isFinished
        } catch {
            saveError = OnboardingError.savedStateUnreadable
        }
    }

    private static func savedState(in store: Store?) throws -> Saved? {
        guard let store, let saved = try stateKey.load(from: store) else { return nil }
        guard OnboardingScreen.allCases.indices.contains(saved.index) else {
            throw OnboardingError.savedStateUnreadable
        }
        return saved
    }

    private func save() {
        guard let store else { return }
        do {
            let saved = Saved(index: index, isFinished: isFinished)
            try Self.stateKey.save(saved, to: store)
            saveError = nil
        } catch {
            saveError = OnboardingError.notSaved(error.localizedDescription)
        }
    }

    var screen: OnboardingScreen { screens[index] }
    var isFirst: Bool { index == 0 }
    var isLast: Bool { index == screens.count - 1 }
    var canContinue: Bool {
        switch screen {
        case .you: identityModel.identity.hasName
        case .team: teamModel.team.name.cleaned != nil
        case .welcome, .sources, .done: true
        }
    }

    func next() {
        guard canContinue else { return }
        if screen == .you { teamModel.reload() }
        if screen == .team { teamModel.save() }
        if isLast {
            isFinished = true
        } else {
            index += 1
        }
    }

    func back() {
        index = max(index - 1, 0)
    }

    /// What the person must read: the setup or the name did not save, or the saved setup was unreadable.
    var problem: String? {
        saveError?.localizedDescription
            ?? identityModel.saveError.map { "Your name was not saved: \($0.localizedDescription)" }
            ?? teamModel.problem
    }
}

enum OnboardingError: Error, Equatable, LocalizedError {
    case savedStateUnreadable
    case notSaved(String)

    var errorDescription: String? {
        switch self {
        case .savedStateUnreadable: "Workbench could not read your saved setup, so setup starts again."
        case .notSaved(let reason): "Your setup was not saved: \(reason)"
        }
    }
}
