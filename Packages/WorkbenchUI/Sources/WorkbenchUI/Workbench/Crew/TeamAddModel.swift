import Observation
import WorkbenchCore

/// Adds a team from a built-in template beside the teams that are there. `Store.addTeam` makes every folder and
/// machine; this model only holds the choice and what that call started.
@Observable
final class TeamAddModel {
    let templates: [TeamTemplate]
    var chosen: TeamTemplate?
    var name = ""
    private(set) var started: TeamStart?
    let problems = ProblemSlot()

    @ObservationIgnored private let crew: Crew

    init(crew: Crew, templates: [TeamTemplate] = TeamTemplate.builtIn) {
        self.crew = crew
        self.templates = templates
    }

    var canAdd: Bool { chosen != nil && started == nil }

    func add() {
        guard let chosen else { return }
        problems.attempt("add the team") { started = try crew.store.addTeam(chosen, name: name) }
        crew.reload()
    }

    /// The machines whose picker waits for the person, from the prompts that starting the team returned.
    var choosers: [HelperModel] {
        (started?.prompts ?? []).compactMap { prompt in
            guard case .picker = prompt.block, let machine = prompt.machine else { return nil }
            return crew.helper(id: machine)
        }
    }
}
