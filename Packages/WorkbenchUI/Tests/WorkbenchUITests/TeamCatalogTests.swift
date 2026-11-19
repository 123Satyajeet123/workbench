import CaptureService
import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

@Suite struct TeamCatalogTests {
    private func setup() throws -> (TeamCatalogModel, Crew, Store) {
        let store = try scratchStore()
        try store.seedMachines(MachineTemplate.seeded.map { ($0.spec, $0.name) })
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "" }, notifier: FakeNotifier())
        return (TeamCatalogModel(store: store, crew: crew, author: { "Kabir" }), crew, store)
    }

    @Test func sharingNeedsAFolderThenWritesOnlyTheFoundersFile() throws {
        let (catalog, crew, store) = try setup()
        let pip = try #require(crew.crew.first)
        catalog.share(pip)
        #expect(catalog.problem?.contains("team folder") == true)
        let folder = scratchFolder()
        catalog.choose(folder)
        catalog.share(pip)
        #expect(catalog.isShared(pip) && catalog.teammates.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["Kabir--team.ledger.json"])
        let reopened = TeamCatalogModel(store: store, crew: crew, author: { "Kabir" })
        #expect(reopened.folder == folder && reopened.isShared(pip))
        catalog.unshare(pip)
        #expect(!catalog.isShared(pip))
    }

    @Test func aTeammatesMachineShowsWithItsRecordAndAdoptingItStartsAtZeroTrust() throws {
        let (catalog, crew, store) = try setup()
        let folder = scratchFolder()
        catalog.choose(folder)
        var record = SharedMachine.Record()
        record.runs = 12
        record.heldOutAnswers = 22
        let theirs = Machine(
            id: 7, name: "Inbound deals", template: HelperSpec.team.task,
            spec: {
                var spec = HelperSpec.team
                spec.brief = "List each startup that wrote to the fund."
                return spec
            }(),
            state: .active)
        try SharedMachine(author: "Aditya", machine: theirs, record: record, at: .now).write(to: folder)
        catalog.refresh()
        let shared = try #require(catalog.teammates.first)
        #expect(shared.author == "Aditya" && shared.record.runs == 12)
        guard case .earned = shared.record.trust else {
            Issue.record("22 right held-out answers earn trust for its author")
            return
        }
        let id = try #require(catalog.adopt(shared))
        let mine = try #require(crew.helper(id: id))
        #expect(mine.name == "Inbound deals" && mine.spec.brief == "List each startup that wrote to the fund.")
        #expect(mine.spec.task != theirs.spec.task)
        #expect(try store.queries.quality().first { $0.task == mine.spec.task } == nil, "trust starts at zero")
    }
}
