import Foundation

extension Store {
    /// Adds each built-in machine the store has never held. A machine the founder deleted is not added again.
    public func seedMachines(_ builtIns: [(spec: HelperSpec, name: String)]) throws {
        try database.transaction {
            for (spec, name) in builtIns
            where try database.rows("SELECT 1 FROM machine WHERE task = ?", [.text(spec.task)]).isEmpty {
                try addMachine(spec: spec, template: spec.task, name: name)
            }
        }
    }

    /// A new machine from a template, with its own task so its items, settings and trust are its own. The task is the
    /// template's with a dash, never a dot, so no machine's settings key starts with another machine's task.
    @discardableResult
    public func createMachine(from template: HelperSpec, name: String) throws -> Machine {
        var spec = template
        spec.task = "\(template.task)-\(UUID().uuidString.prefix(8).lowercased())"
        return try database.transaction { try addMachine(spec: spec, template: template.task, name: name) }
    }

    public func rename(_ machine: Machine, to name: String) throws {
        guard let name = name.cleaned else { return }
        try change(machine, name: name, spec: machine.spec, state: machine.state)
    }

    /// A new brief is a new prompt version: the earlier versions' marks and trust stay with them.
    public func edit(_ machine: Machine, brief: String) throws {
        guard let brief = brief.cleaned else { return }
        var spec = machine.spec
        spec.brief = brief
        try change(machine, name: machine.name, spec: spec, state: machine.state)
    }

    public func setState(_ machine: Machine, _ state: Machine.State) throws {
        guard state != .deleted else { return try delete(.machine(machine.task)) }
        try change(machine, name: machine.name, spec: machine.spec, state: state)
    }

    /// The team and its people. Saving replaces the people list; a removed person keeps a removal date.
    public func saveTeam(_ team: Team) throws {
        guard let name = team.name.cleaned else { return }
        try database.transaction {
            let now = SQLValue(clock())
            let id: Int64
            if let existing = try database.rows("SELECT id FROM team LIMIT 1").first?[0].integer {
                try database.run("UPDATE team SET name = ? WHERE id = ?", [.text(name), .int(existing)])
                id = existing
            } else {
                id = try database.run("INSERT INTO team(name, created_at) VALUES (?,?)", [.text(name), now])
            }
            let kept = Set(team.people.compactMap(\.id))
            try database.run(
                "UPDATE member SET removed_at = ? WHERE team_id = ? AND removed_at IS NULL AND id NOT IN (\(kept.map(String.init).joined(separator: ",")))",
                [now, .int(id)])
            for person in team.people {
                guard let name = person.name.cleaned else { continue }
                if let personID = person.id {
                    try database.run(
                        "UPDATE member SET name = ?, role = ?, is_me = ? WHERE id = ?",
                        [.text(name), .text(person.role), .int(person.isMe ? 1 : 0), .int(personID)])
                } else {
                    try database.run(
                        "INSERT INTO member(team_id, name, role, is_me, added_at) VALUES (?,?,?,?,?)",
                        [.int(id), .text(name), .text(person.role), .int(person.isMe ? 1 : 0), now])
                }
            }
        }
    }

    private func addMachine(spec: HelperSpec, template: String, name: String) throws -> Machine {
        let id = try database.run(
            "INSERT INTO machine(task, template, created_at) VALUES (?,?,?)",
            [.text(spec.task), .text(template), SQLValue(clock())])
        let machine = Machine(id: id, name: name, template: template, spec: spec, state: .active)
        try change(machine, name: name, spec: spec, state: .active)
        return machine
    }

    func change(_ machine: Machine, name: String, spec: HelperSpec, state: Machine.State) throws {
        try database.run(
            "INSERT INTO machine_change(machine_id, at, name, spec, state) VALUES (?,?,?,?,?)",
            [.int(machine.id), SQLValue(clock()), .text(name), .text(try Coding.json(spec)), .text(state.rawValue)])
    }
}

extension Queries {
    /// Every machine not deleted, oldest first.
    public func machines() throws -> [Machine] {
        try database.rows(
            "SELECT id, name, template, spec, state FROM machine_now WHERE state <> 'deleted' ORDER BY id"
        ).compactMap { row in
            guard let state = row[4].string.flatMap(Machine.State.init),
                let spec = try? Coding.value(HelperSpec.self, from: row[3].string ?? "")
            else { return nil }
            return Machine(
                id: row[0].integer ?? 0, name: row[1].string ?? "", template: row[2].string ?? "", spec: spec,
                state: state)
        }
    }

    public func team() throws -> Team? {
        guard let team = try database.rows("SELECT id, name FROM team LIMIT 1").first, let id = team[0].integer else {
            return nil
        }
        let people = try database.rows(
            "SELECT id, name, role, is_me FROM member WHERE team_id = ? AND removed_at IS NULL ORDER BY is_me DESC, id",
            [.int(id)]
        ).map {
            Team.Person(id: $0[0].integer, name: $0[1].string ?? "", role: $0[2].string ?? "", isMe: $0[3].integer == 1)
        }
        return Team(name: team[1].string ?? "", people: people)
    }
}
