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
    /// The optional machines of the template the person asked for, by machine template id.
    private(set) var optionalChosen: Set<String> = []
    private(set) var teamIsStarted = false
    /// What the started team's machines wait for the person to do, as starting the team returned it.
    private(set) var prompts: [TeamStart.Prompt] = []
    /// The person took the first look, so the step asks to continue and no longer to skip.
    var hasLookedFirst = false
    private(set) var screen = OnboardingScreen.welcome { didSet { save() } }
    private(set) var isFinished = false { didSet { save() } }
    private(set) var saveError: (any Error)?
    @ObservationIgnored private let store: Store?
    @ObservationIgnored private let teamStarted: () -> Void

    /// A row saved before the screen was kept holds no screen, so it opens the first screen.
    private struct Saved: Codable {
        var screen: OnboardingScreen?
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
            guard let store, let saved = try Self.stateKey.load(from: store) else { return }
            isFinished = saved.isFinished
            if let savedScreen = saved.screen, screens.contains(savedScreen) { screen = savedScreen }
        } catch {
            saveError = OnboardingError.savedStateUnreadable
        }
    }

    private func save() {
        guard let store else { return }
        do {
            let saved = Saved(screen: screen, isFinished: isFinished)
            try Self.stateKey.save(saved, to: store)
            saveError = nil
        } catch {
            saveError = OnboardingError.notSaved(error.localizedDescription)
        }
    }

    /// The chosen template with the optional machines the person asked for. Until the person chooses, it starts nothing.
    var template: TeamTemplate { (teamModel.template ?? .blank).adding(optional: optionalChosen) }
    var needs: [SourceNeed] { template.sourceNeeds }
    /// The questions of the template's machines, asked only when finishing setup makes those machines.
    var questions: [SetupQuestion] { startsTeam ? template.setupQuestions : [] }
    var screens: [OnboardingScreen] {
        OnboardingScreen.allCases.filter { screen in
            switch screen {
            case .setup: !questions.isEmpty
            case .watchlist: startsTeam && template.watchesCompanies
            case .firstLook: startsTeam && !template.seeds.isEmpty
            case .welcome, .you, .team, .connect, .done: true
            }
        }
    }

    var index: Int { screens.firstIndex(of: screen) ?? 0 }
    var isFirst: Bool { index == 0 }
    var isLast: Bool { index == screens.count - 1 }
    var canContinue: Bool {
        switch screen {
        case .you: identityModel.identity.hasName
        case .team: teamModel.team.name.cleaned != nil && (!startsTeam || teamModel.template != nil)
        case .welcome, .connect, .setup, .watchlist, .firstLook, .done: true
        }
    }

    func summary(connected: [String]) -> SetupSummary {
        SetupSummary(
            machines: startsTeam ? template.seeds.map(\.name) : [], keepsMachines: !startsTeam,
            asksSources: !needs.isEmpty, connected: connected, answered: questions.filter { answers[$0] != nil }.count,
            questions: questions.count)
    }

    func include(_ machine: TeamMachine, _ isIncluded: Bool) {
        if isIncluded { optionalChosen.insert(machine.template) } else { optionalChosen.remove(machine.template) }
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
        } else if screens[index + 1] != .firstLook || startTeam() {
            screen = screens[index + 1]
        }
    }

    /// Makes the template's machines once, so the first look has machines to read with.
    @discardableResult
    private func startTeam() -> Bool {
        guard !teamIsStarted else { return true }
        do {
            prompts = try startsTeam ? (store?.addTeam(template, answers: answers).prompts ?? []) : []
            teamStarted()
            teamIsStarted = true
            return true
        } catch {
            saveError = OnboardingError.teamNotStarted(error.localizedDescription)
            return false
        }
    }

    private func finish() {
        if startTeam() { isFinished = true }
    }

    func back() {
        screen = screens[max(index - 1, 0)]
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
