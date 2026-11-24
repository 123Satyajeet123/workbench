import Foundation
import GRDB

extension Store {
    /// Adds each built-in machine the store has never held. A machine the founder deleted is not added again.
    public func seedMachines(_ builtIns: [(spec: HelperSpec, name: String)]) throws {
        try writer.write { db in
            for (spec, name) in builtIns
            where try Int.fetchOne(db, sql: "SELECT 1 FROM machine WHERE task = ?", arguments: [spec.task]) == nil {
                try addMachine(db, spec: spec, template: spec.task, name: name, folder: nil)
            }
        }
    }

    /// Adds a team from `template` beside the teams already in the store: one new top folder for the team, named `name`
    /// (the template's name by default; a number follows it when a live top folder has that name) and marked as a team
    /// of this template, and each gallery item of the template set up under it with `start`. Each answer goes in the
    /// spec of the machine it is for, as a new version of that machine. An item that needs what the app cannot give is
    /// left out and named in the result; the rest of the team still starts. A team with no item to start adds nothing,
    /// not even its folder. No folder or machine that was there is changed, so adding the same template again makes a
    /// second team.
    @discardableResult
    public func addTeam(
        _ template: TeamTemplate, name: String? = nil, answers: SetupAnswers = [:],
        having: Set<GalleryTemplate.Need> = []
    ) throws -> TeamStart {
        let refusals = template.entries.map { $0.item.refusal(having: having) }
        var started = TeamStart()
        guard refusals.contains(where: { $0 == nil }) else {
            started.items = zip(template.entries, refusals).compactMap { entry, refusal in
                refusal.map { .refused(entry.item, $0) }
            }
            return started
        }
        let folder = try writer.write { db in
            let id = try WorkObjectRows.newTeamFolder(db, of: template.id, named: name?.cleaned ?? template.name)
            return try Queries.workObjects(db, where: "id = ?", [id])[0]
        }
        started.folder = folder
        var seeded: [Machine?] = []
        for (entry, refusal) in zip(template.entries, refusals) {
            var machine: Machine?
            if let refusal {
                started.items.append(.refused(entry.item, refusal))
            } else {
                let start = try start(
                    entry.item, parent: folder.id, name: entry.machine.name, overrides: entry.machine.overrides,
                    having: having)
                started.items.append(.started(entry.item, start))
                machine = start.machine
            }
            if entry.item.machine != nil { seeded.append(machine) }
        }
        for question in template.setupQuestions {
            guard let answer = answers[question] else { continue }
            for case let machine? in question.machines.map({ seeded[$0] }) { try apply(answer, to: machine) }
            started.answered += 1
        }
        return started
    }

    /// A new machine from a template, with its own task so its items, settings and trust are its own. The task is the
    /// template's with a dash, never a dot, so no machine's settings key starts with another machine's task.
    /// `template` names the template the spec came from; it defaults to the spec's own task, for a template itself.
    /// The machine gets a page in `folder`, or in the default folder of its template.
    @discardableResult
    public func createMachine(
        from spec: HelperSpec, template: String? = nil, name: String, in folder: WorkObjectID? = nil
    ) throws -> Machine {
        let template = template ?? spec.task
        var spec = spec
        spec.task = "\(template)-\(UUID().uuidString.prefix(8).lowercased())"
        return try writer.write { db in try addMachine(db, spec: spec, template: template, name: name, folder: folder) }
    }

    /// Moves a machine to a newer built-in design: the built-in's brief, fields, lifecycle and checks, with the
    /// machine's own task (so its items, marks and settings stay), model, example policy, what it follows, and its
    /// view when the new design can still fill it. A new design is a new prompt version, so trust is earned again.
    public func upgrade(_ machine: Machine, to builtIn: HelperSpec) throws {
        var spec = builtIn
        spec.task = machine.spec.task
        spec.runner = machine.spec.runner
        spec.examples = machine.spec.examples
        spec.follows = machine.spec.follows ?? builtIn.follows
        spec.criteria = machine.spec.criteria ?? builtIn.criteria
        if spec.views.values.contains(machine.spec.view) { spec.view = machine.spec.view }
        try change(machine, name: machine.name, spec: spec, state: machine.state)
    }

    public func rename(_ machine: Machine, to name: String) throws {
        guard let name = name.cleaned else { return }
        try change(machine, name: name, spec: machine.spec, state: machine.state)
    }

    /// A new brief is a new prompt version: the earlier versions' marks and trust stay with them.
    public func edit(_ machine: Machine, brief: String) throws {
        try revise(machine, brief: brief, examples: machine.spec.examples, runner: machine.spec.runner)
    }

    /// A new brief, example policy or model is a new version of the machine.
    public func revise(_ machine: Machine, brief: String, examples: Int?, runner: String?) throws {
        guard let brief = brief.cleaned else { return }
        var spec = machine.spec
        spec.brief = brief
        spec.examples = examples
        spec.runner = runner
        try change(machine, name: machine.name, spec: spec, state: machine.state)
    }

    /// Shows the machine's items in another view its spec can fill; a view it cannot fill is refused.
    public func show(_ machine: Machine, as view: String) throws {
        guard let chosen = machine.spec.views[view] else { return }
        var spec = machine.spec
        spec.view = chosen
        try change(machine, name: machine.name, spec: spec, state: machine.state)
    }

    public func setState(_ machine: Machine, _ state: Machine.State) throws {
        guard state != .deleted else { return try delete(.machine(machine.task)) }
        try change(machine, name: machine.name, spec: machine.spec, state: state)
    }

    /// The team and its people. Saving replaces the people list; a removed person keeps a removal date.
    public func saveTeam(_ team: Team) throws {
        guard let name = team.name.cleaned else { return }
        try writer.write { db in
            let now = clock().stored
            let id: Int64
            if let existing = try Int64.fetchOne(db, sql: "SELECT id FROM team LIMIT 1") {
                try db.execute(sql: "UPDATE team SET name = ? WHERE id = ?", arguments: [name, existing])
                id = existing
            } else {
                try db.execute(sql: "INSERT INTO team(name, created_at) VALUES (?,?)", arguments: [name, now])
                id = db.lastInsertedRowID
            }
            let kept = Set(team.people.compactMap(\.id))
            try db.execute(
                sql:
                    "UPDATE member SET removed_at = ? WHERE team_id = ? AND removed_at IS NULL AND id NOT IN (\(kept.map(String.init).joined(separator: ",")))",
                arguments: [now, id])
            for person in team.people {
                guard let name = person.name.cleaned else { continue }
                if let personID = person.id {
                    try db.execute(
                        sql: "UPDATE member SET name = ?, role = ?, is_me = ? WHERE id = ?",
                        arguments: [name, person.role, person.isMe ? 1 : 0, personID])
                } else {
                    try db.execute(
                        sql: "INSERT INTO member(team_id, name, role, is_me, added_at) VALUES (?,?,?,?,?)",
                        arguments: [id, name, person.role, person.isMe ? 1 : 0, now])
                }
            }
        }
    }

    @discardableResult
    private func addMachine(
        _ db: Database, spec: HelperSpec, template: String, name: String, folder: WorkObjectID?
    ) throws -> Machine {
        try db.execute(
            sql: "INSERT INTO machine(task, template, created_at) VALUES (?,?,?)",
            arguments: [spec.task, template, clock().stored])
        let id = db.lastInsertedRowID
        let page = try WorkObjectRows.addMachinePage(db, machine: id, template: template, name: name, folder: folder)
        let machine = Machine(id: id, name: name, template: template, spec: spec, state: .active, page: page)
        try change(db, machine, name: name, spec: spec, state: .active)
        return machine
    }

    func change(_ machine: Machine, name: String, spec: HelperSpec, state: Machine.State) throws {
        try writer.write { db in try change(db, machine, name: name, spec: spec, state: state) }
    }

    func change(_ db: Database, _ machine: Machine, name: String, spec: HelperSpec, state: Machine.State) throws {
        try db.execute(
            sql: "INSERT INTO machine_change(machine_id, at, name, spec, state) VALUES (?,?,?,?,?)",
            arguments: [machine.id, clock().stored, name, try Coding.json(spec), state.rawValue])
        try db.execute(
            sql: "UPDATE work_object SET name = ? WHERE id = (SELECT page_id FROM machine WHERE id = ?)",
            arguments: [name, machine.id])
    }
}

extension Queries {
    /// Whether the store ever held a machine, deleted or not.
    public func holdsMachine() throws -> Bool {
        try reader.read { db in try Int.fetchOne(db, sql: "SELECT 1 FROM machine LIMIT 1") != nil }
    }

    /// Every machine not deleted, oldest first.
    public func machines() throws -> [Machine] {
        try reader.read { db in
            try db.fetch(
                "machine_now",
                "SELECT \(Machine.columns) FROM machine_now WHERE state <> 'deleted' ORDER BY id",
                as: Machine.init(row:))
        }
    }

    /// The folder a new machine of `template` lands in: the one asked for, else the live root folder of its gallery
    /// item. Nil when the store has no such folder yet.
    public func folder(forNewMachineOf template: String, in folder: WorkObjectID?) throws -> WorkObjectID? {
        if let folder { return folder }
        return try reader.read { db in
            try WorkObjectRows.keyedChild(
                db, parent: nil, key: GalleryTemplate.folder(forMachine: template).key)
        }
    }

    public func team() throws -> Team? {
        try reader.read { db in
            let teams = try db.fetch("team", "SELECT id, name FROM team LIMIT 1") { row in
                (id: try row.value("id") as Int64, name: try row.value("name") as String)
            }
            guard let team = teams.first else { return nil }
            let people = try db.fetch(
                "member",
                "SELECT id, name, role, is_me FROM member WHERE team_id = ? AND removed_at IS NULL ORDER BY is_me DESC, id",
                [team.id], as: Team.Person.init(row:))
            return Team(name: team.name, people: people)
        }
    }
}

extension Machine {
    init(row: Row) throws {
        let template: String = try row.value("template")
        self.init(
            id: try row.value("id"), name: try row.value("name"), template: template,
            spec: (try row.json("spec") as HelperSpec).filling(from: MachineTemplate.of(id: template)?.spec),
            state: try row.enumeration("state"), page: try row.optionalValue("page_id"),
            folder: try row.optionalValue("folder"))
    }

    static let columns = """
        machine_now.id, machine_now.name, machine_now.template, machine_now.spec, machine_now.state, \
        machine_now.page_id, (SELECT parent_id FROM work_object WHERE id = machine_now.page_id) AS folder
        """
}

extension Team.Person {
    init(row: Row) throws {
        self.init(
            id: try row.optionalValue("id"), name: try row.value("name"), role: try row.value("role"),
            isMe: try row.value("is_me") as Int64 == 1)
    }
}
