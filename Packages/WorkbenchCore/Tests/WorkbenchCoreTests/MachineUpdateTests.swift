import Foundation
import Testing

@testable import WorkbenchCore

/// A machine made from an older built-in can take the newer design and keep its own items, marks and settings.
@Suite struct MachineUpdateTests {
    /// Pip as it shipped before it became the fact machine.
    private var oldPip: HelperSpec {
        var spec = HelperSpec.team
        spec.fields = spec.fields.filter { ["person", "kind", "text", "eta"].contains($0.name) }
        spec.lifecycle = nil
        spec.brief = "You keep a team ledger."
        return spec
    }

    @Test func anOlderDesignSaysWhatTheUpdateAddsAndACurrentOneSaysNothing() throws {
        let changes = try #require(oldPip.update(toward: .team))
        #expect(changes.contains("adds project") && changes.contains("lets facts open and close"))
        #expect(HelperSpec.team.update(toward: .team) == nil)
        var editedBrief = HelperSpec.team
        editedBrief.brief = "The founder's own improved brief."
        #expect(editedBrief.update(toward: .team) == nil, "a brief edit alone is no update")
    }

    @Test func anUpdateKeepsTheTaskModelExamplesAndAViewItCanStillFill() throws {
        let store = try makeStore()
        var spec = oldPip
        spec.runner = "codex gpt-6.2-sol"
        spec.examples = 4
        let machine = try store.createMachine(from: spec, template: HelperSpec.team.task, name: "Pip")
        try store.upgrade(machine, to: .team)
        let updated = try #require(try store.queries.machines().first { $0.id == machine.id })
        #expect(updated.task == machine.task, "items, marks and settings stay with the same task")
        #expect(updated.spec.runner == "codex gpt-6.2-sol" && updated.spec.examples == 4)
        #expect(updated.spec.lifecycle == HelperSpec.team.lifecycle && updated.spec.brief == HelperSpec.team.brief)
        #expect(updated.spec.view == machine.spec.view)
        #expect(updated.spec.update(toward: .team) == nil)
    }
}
