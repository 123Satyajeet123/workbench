import CaptureService
import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

@Suite struct GroupedViewTests {
    @Test func dealIntakeCanShowItsDealsByRatingAndAProposalCanAskForIt() throws {
        let store = try scratchStore()
        let machine = try store.createMachine(from: .dealIntake, name: "Deal intake")
        try store.show(machine, as: "by rating")
        #expect(try store.queries.machines().first?.spec.view == .grouped(by: "rating"))
        try store.show(try #require(try store.queries.machines().first), as: "by sector")
        #expect(
            try store.queries.machines().first?.spec.view == .grouped(by: "rating"), "sector is free text, no group")
        let templates = MachineTemplate.all.map {
            Mochi.Template(id: $0.spec.task, does: $0.detail, views: Array($0.spec.views.keys))
        }
        #expect(templates.first { $0.id == "vc.deals" }?.views == ["by rating", "by stage", "table"])
    }
}
