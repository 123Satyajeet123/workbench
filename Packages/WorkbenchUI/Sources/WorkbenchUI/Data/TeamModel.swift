import Foundation
import Observation
import WorkbenchCore

@Observable
final class TeamModel {
    var team: Team
    private(set) var problem: String?

    @ObservationIgnored private let store: Store?
    @ObservationIgnored private let me: () -> String

    init(store: Store?, me: @escaping () -> String) {
        self.store = store
        self.me = me
        team = Team(name: "", people: [])
        reload()
    }

    func reload() {
        do {
            team = try store?.queries.team() ?? Team(name: "", people: [])
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
            reload()
        } catch {
            problem = "Your team was not saved: \(error.localizedDescription)"
        }
    }
}
