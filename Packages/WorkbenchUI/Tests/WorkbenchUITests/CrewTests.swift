import CaptureService
import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

@Suite struct CrewTests {
    private func crew() throws -> (Crew, Store) {
        let store = try scratchStore()
        try store.seedMachines(MachineTemplate.seeded.map { ($0.spec, $0.name) })
        let capture = try CaptureService(store: store)
        return (Crew(store: store, capture: capture, founder: { "Kabir" }, notifier: FakeNotifier()), store)
    }

    @Test func theCrewComesFromTheStoreAndMochiHoldsTheTimeline() throws {
        let (crew, _) = try crew()
        #expect(crew.machines.map(\.name) == ["Pip", "Timeline"])
        #expect(crew.timeline?.spec.task == HelperSpec.timeline.task)
        #expect(crew.crew.map(\.name) == ["Pip"])
    }

    @Test func aMachineIsAddedRenamedGivenANewBriefPausedAndDeleted() throws {
        let (crew, store) = try crew()
        let id = try #require(crew.create(from: .team, name: "Deal intake"))
        let deals = try #require(crew.helper(id: id))
        #expect(crew.crew.map(\.name) == ["Pip", "Deal intake"])
        crew.rename(deals, to: "Inbound deals")
        #expect(crew.helper(id: id) === deals && deals.name == "Inbound deals")
        crew.edit(deals, brief: "List each new startup that wrote to us, with its sector.")
        #expect(deals.spec.brief == "List each new startup that wrote to us, with its sector.")
        crew.setPaused(deals, true)
        #expect(deals.isPaused)
        crew.setPaused(deals, false)
        #expect(!deals.isPaused)
        crew.delete(deals)
        #expect(crew.helper(id: id) == nil && crew.crew.map(\.name) == ["Pip"])
        #expect(try store.queries.machines().map(\.name) == ["Pip", "Timeline"])
        #expect(crew.problem == nil)
    }

    @Test func aPausedMachineReadsNothing() async throws {
        let store = try scratchStore()
        try store.savePolicy(CapturePolicy(switches: [.screen: true]))
        let model = ScriptedModel(#"{"items":[]}"#)
        let capture = try CaptureService(store: store)
        let crew = Crew(
            store: store, capture: capture, founder: { "" }, makeModel: { _ in RecordedModel(model, store: store) },
            notifier: FakeNotifier())
        let id = try #require(crew.create(from: .timeline, name: "Second timeline"))
        let helper = try #require(crew.helper(id: id))
        crew.setPaused(helper, true)
        await helper.read()
        #expect(model.inputs.withLock { $0.isEmpty })
        #expect(helper.phase == .idle)
    }

    @Test func aPageSurvivesARestartByItsRawValue() {
        for page in [SidebarSelection.day, .calls, .crew, .advanced, .machine(42)] {
            #expect(SidebarSelection(rawValue: page.rawValue) == page)
        }
        #expect(SidebarSelection(rawValue: "team") == nil && SidebarSelection(rawValue: "machine:x") == nil)
    }
}

@Suite struct TeamSetupTests {
    @Test func setupAsksForATeamAddsTheFounderAndSavesThePeople() throws {
        let store = try scratchStore()
        let identity = IdentityModel(store: store)
        let model = OnboardingModel(store: store, identity: identity)
        identity.identity.name = "Kabir"
        model.next()
        model.next()
        #expect(model.screen == .team)
        #expect(model.teamModel.team.people.map(\.name) == ["Kabir"])
        model.next()
        #expect(model.screen == .team, "a team needs a name")
        model.teamModel.team.name = "Brave"
        model.teamModel.addPerson()
        model.teamModel.team.people[1].name = "Aditya"
        model.teamModel.team.people[1].role = "Analyst"
        model.next()
        #expect(model.screen == .connect)
        let saved = try #require(try store.queries.team())
        #expect(saved.name == "Brave" && saved.people.map(\.name) == ["Kabir", "Aditya"])
        model.teamModel.remove(at: 0)
        #expect(model.teamModel.team.people.count == 2, "the founder cannot be removed")
    }
}

@Suite struct MachineUpdateOfferTests {
    @Test func theLivePipOfAnEarlierVersionIsOfferedTheUpdateOnceAndKeepsItsTask() throws {
        let store = try scratchStore()
        var old = HelperSpec.team
        old.fields = old.fields.filter { ["person", "kind", "text", "eta"].contains($0.name) }
        old.lifecycle = nil
        try store.seedMachines([(old, "Pip"), (HelperSpec.timeline, "Timeline")])
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "Kabir" }, notifier: FakeNotifier())
        let pip = try #require(crew.machines.first { $0.name == "Pip" })
        let timeline = try #require(crew.machines.first { $0.name == "Timeline" })
        #expect(crew.update(for: timeline) == nil, "a current design is not offered anything")
        let offer = try #require(crew.update(for: pip))
        #expect(offer.changes.contains("lets facts open and close"))

        crew.upgrade(pip)
        let updated = try #require(crew.machines.first { $0.name == "Pip" })
        #expect(updated.spec.task == HelperSpec.team.task && updated.spec.lifecycle != nil)
        #expect(crew.update(for: updated) == nil)
    }
}
