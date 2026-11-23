import Foundation
import Observation
import WorkbenchCore

/// The founder's team, its people and the template it started from, edited in setup and in Settings, saved when the
/// founder commits.
@Observable
final class TeamModel {
    var team: Team
    var template: TeamTemplate
    let templates: [TeamTemplate]
    private(set) var problem: String?

    private static let templateKey = StateKey<String>.text("team.template")

    @ObservationIgnored private let store: Store?
    @ObservationIgnored private let me: () -> String

    init(store: Store?, me: @escaping () -> String, templates: [TeamTemplate] = TeamTemplate.builtIn) {
        self.store = store
        self.me = me
        self.templates = templates
        template = templates[0]
        team = Team(name: "", people: [])
        reload()
    }

    func reload() {
        do {
            team = try store?.queries.team() ?? Team(name: "", people: [])
            template = try savedTemplate() ?? template
            problem = nil
        } catch {
            problem = "Your team could not be read: \(error.localizedDescription)"
        }
        if !team.people.contains(where: \.isMe), let name = me().cleaned {
            team.people.insert(.init(name: name, role: "Founder", isMe: true), at: 0)
        }
    }

    func addPerson() { team.people.append(.init(name: "", role: "")) }

    func remove(at index: Int) {
        guard team.people.indices.contains(index), !team.people[index].isMe else { return }
        team.people.remove(at: index)
    }

    func save() {
        guard let store else { return }
        do {
            try store.saveTeam(team)
            try Self.templateKey.save(template.id, to: store)
            reload()
        } catch {
            problem = "Your team was not saved: \(error.localizedDescription)"
        }
    }

    private func savedTemplate() throws -> TeamTemplate? {
        guard let store, let id = try Self.templateKey.load(from: store) else { return nil }
        return templates.first { $0.id == id }
    }
}
