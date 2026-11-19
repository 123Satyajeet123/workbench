import Foundation
import Testing

@testable import WorkbenchCore

@Suite struct MachineReviewTests {
    private func shared(brief: String) -> SharedMachine {
        var spec = HelperSpec.dealIntake
        spec.task = "vc.deals-1234abcd"
        spec.brief = brief
        let machine = Machine(id: 1, name: "Deal intake", template: "vc.deals", spec: spec, state: .active)
        return SharedMachine(author: "Aditya", machine: machine, record: .init(), at: t0)
    }

    @Test func onlyAnotherPersonsApprovalOfThisVersionCounts() {
        let machine = shared(brief: "Rate by sector and stage.")
        let reviews = [
            MachineReview(reviewer: "Aditya", of: machine, approve: true, note: "mine", at: t0),
            MachineReview(reviewer: "Kabir", of: machine, approve: true, note: "good", at: t0),
            MachineReview(reviewer: "Asha", of: machine, approve: false, note: "too loose", at: t0),
        ]
        #expect(machine.approvers(in: reviews) == ["Kabir"])
        let changed = shared(brief: "Rate by sector, stage and revenue.")
        #expect(changed.version != machine.version)
        #expect(changed.approvers(in: reviews).isEmpty, "a changed spec needs a new review")
    }

    @Test func eachReviewerWritesTheirOwnFileBesideTheMachines() throws {
        let folder = temporaryDirectory()
        let machine = shared(brief: "Rate by sector and stage.")
        try machine.write(to: folder)
        try MachineReview(reviewer: "Kabir", of: machine, approve: true, note: "good", at: t0).write(to: folder)
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: folder.appending(path: "reviews").path) == [
                "Kabir--Aditya--vc.deals-1234abcd.json"
            ])
        #expect(SharedMachine.read(from: folder).files.map(\.author) == ["Aditya"])
        #expect(machine.approvers(in: MachineReview.read(from: folder).files) == ["Kabir"])
    }
}
