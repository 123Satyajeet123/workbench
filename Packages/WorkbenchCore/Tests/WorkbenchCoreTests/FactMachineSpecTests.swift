import Foundation
import Testing

@testable import WorkbenchCore

@Suite struct FactMachineSpecTests {
    @Test func theFactMachineKeepsPipsTaskAndFieldsAndOpensPlansAndBlockers() {
        let spec = HelperSpec.team
        #expect(spec.task == "team.ledger")
        #expect(spec.fields.map(\.name) == ["person", "project", "kind", "text", "eta", "stance", "asks"])
        #expect(spec.lifecycle?.field == "kind")
        #expect(spec.lifecycle?.open == ["plan", "blocker", "commitment", "question", "decision"])
        #expect(spec.lifecycle?.outcomes == ["kept", "answered", "resolved", "reversed", "dropped"])
    }

    @Test func theBoardByPersonIsTheDefaultAndProjectsHaveTheirOwnViews() {
        let spec = HelperSpec.team
        #expect(spec.view == .board(groupBy: "person", expected: "members"))
        #expect(
            Set(spec.views.keys) == [
                "table", "board", "by kind", "by project", "by stance", "by asks", "open by project",
            ])
        #expect(spec.views["open by project"] == .checklist(by: "project"))
        #expect(spec.views["by project"] == .grouped(by: "project"))
    }

    @Test func aProjectMustNotBeEmptyAndTheModelIsToldToReuseTheList() {
        let reader = HelperReader(spec: .team, model: RecordedModel(ScriptedModel("{}"), store: try! makeStore()))
        #expect(reader.instructions.contains("- project: reuse a name from the topics list when it fits"))
    }
}
