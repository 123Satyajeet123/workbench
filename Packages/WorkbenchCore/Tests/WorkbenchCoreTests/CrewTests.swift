import Foundation
import Testing

@testable import WorkbenchCore

private let day = WorkDay(containing: t0)

private func addItem(to machine: Machine, in store: Store) async throws -> Item {
    let model = RecordedModel(ScriptedModel(#"{"items":[]}"#), store: store)
    let (_, run) = try await model.generate(
        HelperReader.Reply.self, schema: .object([.init("items", .array(.string))]), task: machine.task,
        instructions: machine.spec.brief, input: "x", holding: [])
    let item = Item(
        task: machine.task, day: day, scope: "", source: machine.spec.source.consent, citeFirst: 1, citeLast: 1,
        start: day.start,
        end: day.start.addingTimeInterval(600), fields: ["task": "t"], quote: "q", run: run)
    try store.saveReading(
        .init(items: [item], dropped: 0, run: run), of: machine.spec, day: day, scope: "",
        grant: grant(machine.spec.source.consent))
    return try #require(store.queries.items(of: machine.task, day: day, scope: "").first)
}

@Suite struct MachineTests {
    @Test func builtInsAreAddedOnceAndADeletedOneDoesNotComeBack() throws {
        let store = try makeStore()
        try store.seedMachines([(.team, "Pip"), (.timeline, "Timeline")])
        try store.seedMachines([(.team, "Pip"), (.timeline, "Timeline")])
        #expect(try store.queries.machines().map(\.name) == ["Pip", "Timeline"])
        try store.setState(try #require(store.queries.machines().first), .deleted)
        try store.seedMachines([(.team, "Pip"), (.timeline, "Timeline")])
        #expect(try store.queries.machines().map(\.name) == ["Timeline"])
    }

    @Test func aMachineMadeFromATemplateHasItsOwnTask() throws {
        let store = try makeStore()
        try store.seedMachines([(.team, "Pip")])
        let deals = try store.createMachine(from: .team, name: "Deal intake")
        #expect(deals.task != HelperSpec.team.task && deals.task.hasPrefix(HelperSpec.team.task + "-"))
        #expect(deals.spec.brief == HelperSpec.team.brief && deals.template == HelperSpec.team.task)
        #expect(try store.queries.machines().map(\.name) == ["Pip", "Deal intake"])
    }

    @Test func aRenameKeepsItemsAndAnEditedBriefIsANewPromptVersion() async throws {
        let store = try makeStore()
        let machine = try store.createMachine(from: .timeline, name: "Timeline")
        _ = try await addItem(to: machine, in: store)
        try store.rename(machine, to: "My day")
        let renamed = try #require(store.queries.machines().first)
        #expect(renamed.name == "My day" && renamed.task == machine.task)
        #expect(try store.queries.items(of: machine.task, day: day, scope: "").count == 1)
        try store.edit(renamed, brief: "Only work blocks longer than 30 minutes.")
        let edited = try #require(store.queries.machines().first)
        #expect(edited.spec.brief == "Only work blocks longer than 30 minutes." && edited.task == machine.task)
        _ = try await addItem(to: edited, in: store)
        #expect(try store.queries.prompts(task: machine.task).count == 2)
        try store.rename(edited, to: "   ")
        #expect(try store.queries.machines().first?.name == "My day")
    }

    @Test func pausingAndResumingKeepTheMachine() throws {
        let store = try makeStore()
        let machine = try store.createMachine(from: .timeline, name: "Timeline")
        try store.setState(machine, .paused)
        #expect(try store.queries.machines().first?.state == .paused)
        try store.setState(try #require(store.queries.machines().first), .active)
        #expect(try store.queries.machines().first?.state == .active)
    }

    @Test func deletingAMachineRemovesItsItemsMarksAndSettingsButNoOtherMachines() async throws {
        let store = try makeStore()
        try store.seedMachines([(.timeline, "Timeline")])
        let pip = try #require(store.queries.machines().first)
        let copy = try store.createMachine(from: .timeline, name: "Copy of Pip")
        let pipItem = try await addItem(to: pip, in: store)
        try store.mark(item: try #require(pipItem.id), as: .confirmed)
        _ = try await addItem(to: copy, in: store)
        for task in [pip.task, copy.task] { try store.saveState("chosen", forKey: "\(task).chat") }
        try store.setState(pip, .deleted)
        #expect(try store.queries.machines().map(\.name) == ["Copy of Pip"])
        #expect(try store.queries.items(of: pip.task, day: day, scope: "").isEmpty)
        #expect(try store.queries.count(of: .mark) == 0)
        #expect(try store.queries.state(forKey: "\(pip.task).chat") == nil)
        #expect(try store.queries.items(of: copy.task, day: day, scope: "").count == 1)
        #expect(try store.queries.state(forKey: "\(copy.task).chat") == "chosen")
        #expect(try store.queries.runs().count == 2)
    }
}

@Suite struct TeamTests {
    @Test func aTeamWithItsPeopleIsSavedEditedAndReadBack() throws {
        let store = try makeStore()
        #expect(try store.queries.team() == nil)
        try store.saveTeam(
            Team(
                name: "Brave",
                people: [
                    .init(name: "Kabir", role: "Founder", isMe: true), .init(name: "Aditya", role: "Analyst"),
                    .init(name: "Asha", role: "Engineer"),
                ]))
        let found = try store.queries.team()
        let saved = try #require(found)
        #expect(saved.name == "Brave" && saved.people.map(\.name) == ["Kabir", "Aditya", "Asha"])
        #expect(saved.people.first?.isMe == true)
        var edited = saved
        edited.name = "Brave Capital"
        edited.people.removeAll { $0.name == "Asha" }
        edited.people[1].role = "Associate"
        try store.saveTeam(edited)
        let reopened = try store.reopened()
        let reread = try reopened.queries.team()
        let again = try #require(reread)
        #expect(again.name == "Brave Capital" && again.people.map(\.name) == ["Kabir", "Aditya"])
        #expect(again.people[1].role == "Associate")
        try store.saveTeam(Team(name: "  ", people: []))
        #expect(try store.queries.team()?.name == "Brave Capital")
    }

    @Test func aGroupMemberTickedAsATeammateIsLinkedOnceAndUntickingRemovesThem() throws {
        let store = try makeStore()
        try store.addTeammate("Asha", whatsapp: "a@s.whatsapp.net")
        try store.addTeammate("Asha", whatsapp: "a@s.whatsapp.net")
        try store.addTeammate("Dev", whatsapp: "d@s.whatsapp.net")
        let team = try #require(try store.queries.team())
        #expect(team.people.map(\.name) == ["Asha", "Dev"])
        #expect(Set(try store.queries.whatsappLinks().values) == ["a@s.whatsapp.net", "d@s.whatsapp.net"])

        try store.removeTeammate(whatsapp: "a@s.whatsapp.net")
        #expect(try store.queries.team()?.people.map(\.name) == ["Dev"])
        try store.addTeammate("Asha", whatsapp: "a@s.whatsapp.net")
        #expect(try store.queries.team()?.people.map(\.name) == ["Dev", "Asha"])
    }

    @Test func tickingATeammateKeepsTheTeamNamedAtOnboarding() throws {
        let store = try makeStore()
        try store.saveTeam(Team(name: "Brave", people: [.init(name: "Kabir", role: "Founder", isMe: true)]))
        try store.addTeammate("Asha", whatsapp: "a@s.whatsapp.net")
        let team = try #require(try store.queries.team())
        #expect(team.name == "Brave" && team.people.map(\.name) == ["Kabir", "Asha"])
    }
}
