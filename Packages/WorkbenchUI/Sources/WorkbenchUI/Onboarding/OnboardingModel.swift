import Foundation
import Observation
import WorkbenchCore

@Observable
final class OnboardingModel {
    let identityModel: IdentityModel
    let teamModel: TeamModel
    /// Whether finishing setup makes the template's machines: true for a store that never held a machine.
    let startsTeam: Bool
    private(set) var answers: SetupAnswers = [:]
    private(set) var index = 0 { didSet { save() } }
    private(set) var isFinished = false { didSet { save() } }
    private(set) var saveError: (any Error)?
    @ObservationIgnored private let store: Store?
    @ObservationIgnored private let teamStarted: () -> Void

    private struct Saved: Codable {
        var index: Int
        var isFinished: Bool
    }

    private static let stateKey = StateKey<Saved>.json("onboarding")

    init(
        store: Store? = nil, identity: IdentityModel = IdentityModel(), team: TeamModel? = nil,
        teamStarted: @escaping () -> Void = {}
    ) {
        self.store = store
        self.teamStarted = teamStarted
        identityModel = identity
        teamModel = team ?? TeamModel(store: store, me: { identity.identity.name })
        startsTeam = (try? store?.queries.holdsMachine()) != true
        do {
            guard let saved = try savedState() else { return }
            index = saved.index
            isFinished = saved.isFinished
        } catch {
            saveError = OnboardingError.savedStateUnreadable
        }
    }

    private func savedState() throws -> Saved? {
        guard let store, let saved = try Self.stateKey.load(from: store) else { return nil }
        guard screens.indices.contains(saved.index) else { throw OnboardingError.savedStateUnreadable }
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

    var template: TeamTemplate { teamModel.template }
    var needs: [SourceNeed] { template.sourceNeeds }
    /// The questions of the template's machines, asked only when finishing setup makes those machines.
    var questions: [SetupQuestion] { startsTeam ? template.setupQuestions : [] }
    var screens: [OnboardingScreen] { OnboardingScreen.allCases.filter { $0 != .setup || !questions.isEmpty } }

    var screen: OnboardingScreen { screens[index] }
    var isFirst: Bool { index == 0 }
    var isLast: Bool { index == screens.count - 1 }
    var canContinue: Bool {
        switch screen {
        case .you: identityModel.identity.hasName
        case .team: teamModel.team.name.cleaned != nil
        case .welcome, .connect, .setup, .done: true
        }
    }

    func summary(connected: [String]) -> SetupSummary {
        SetupSummary(
            machines: startsTeam ? template.seeds.map(\.name) : [], keepsMachines: !startsTeam,
            asksSources: !needs.isEmpty, connected: connected, answered: questions.filter { answers[$0] != nil }.count,
            questions: questions.count)
    }

    func answer(_ question: SetupQuestion, with answer: SetupAnswer) { answers[question] = answer }

    func useDefaults(for question: SetupQuestion) { answers[question] = nil }

    /// The spec the template gives the first machine a question is about, before any answer.
    func templateSpec(of question: SetupQuestion) -> HelperSpec { template.seeds[question.machines[0]].spec }

    func next() {
        guard canContinue else { return }
        if screen == .you { teamModel.reload() }
        if screen == .team { teamModel.save() }
        if isLast {
            finish()
        } else {
            index += 1
        }
    }

    private func finish() {
        do {
            try store?.startTeam(from: template, answers: answers)
            teamStarted()
            isFinished = true
        } catch {
            saveError = OnboardingError.teamNotStarted(error.localizedDescription)
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
    case teamNotStarted(String)

    var errorDescription: String? {
        switch self {
        case .savedStateUnreadable: "Workbench could not read your saved setup, so setup starts again."
        case .notSaved(let reason): "Your setup was not saved: \(reason)"
        case .teamNotStarted(let reason): "Your team’s machines were not made: \(reason)"
        }
    }
}
