import CaptureService
import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

@Suite struct TeamCatalogTests {
    private let secrets = MemorySecrets()

    private func setup(_ name: String = "Kabir") throws -> (TeamCatalogModel, Crew, Store) {
        let store = try scratchStore()
        try store.seedMachines(MachineTemplate.seeded.map { ($0.spec, $0.name) })
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "" }, notifier: FakeNotifier())
        return (TeamCatalogModel(store: store, crew: crew, author: { name }, secrets: secrets), crew, store)
    }

    @Test func sharingNeedsAFolderThenWritesOnlyTheFoundersFile() throws {
        let (catalog, crew, store) = try setup()
        let pip = try #require(crew.crew.first)
        catalog.share(pip)
        #expect(catalog.problem?.contains("team folder") == true)
        let folder = scratchFolder()
        catalog.choose(folder)
        catalog.foundTeam()
        catalog.share(pip)
        #expect(catalog.isShared(pip) && catalog.teammates.isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(names == ["sync"], "one folder of envelopes; no plaintext machine file")
        let reopened = TeamCatalogModel(store: store, crew: crew, author: { "Kabir" }, secrets: secrets)
        #expect(reopened.folder == folder && reopened.isShared(pip))
        catalog.unshare(pip)
        #expect(!catalog.isShared(pip))
    }

    @Test func aTeammatesMachineShowsWithItsRecordAndAdoptingItStartsAtZeroTrust() throws {
        let (catalog, crew, store) = try setup()
        let aditya = TeamCatalogModel(
            store: try scratchStore(), crew: crew, author: { "Aditya" }, secrets: MemorySecrets())
        let folder = scratchFolder()
        catalog.choose(folder)
        aditya.choose(folder)
        formTeam(founder: catalog, others: [aditya])
        var record = SharedMachine.Record()
        record.runs = 12
        record.trust = .earned(bound: 0.0885)
        let theirs = Machine(
            id: 7, name: "Inbound deals", template: HelperSpec.team.task,
            spec: {
                var spec = HelperSpec.team
                spec.brief = "List each startup that wrote to the fund."
                spec.view = .table
                return spec
            }(),
            state: .active)
        try aditya.send([.machine(SharedMachine(author: "Aditya", machine: theirs, record: record, at: .now))])
        catalog.refresh()
        let shared = try #require(catalog.teammates.first)
        #expect(shared.author == "Aditya" && shared.record.runs == 12)
        guard case .earned = shared.record.trust else {
            Issue.record("an earned record shows as trusted for its author")
            return
        }
        let id = try #require(catalog.adopt(shared))
        let mine = try #require(crew.helper(id: id))
        #expect(mine.name == "Inbound deals" && mine.spec.brief == "List each startup that wrote to the fund.")
        #expect(mine.spec.view == .table && mine.machine.template == HelperSpec.team.task, "the whole spec comes along")
        #expect(mine.spec.task != theirs.spec.task)
        #expect(try store.queries.quality().first { $0.task == mine.spec.task } == nil, "trust starts at zero")
    }

    @Test func aStrangersPlaintextFileInTheTeamFolderIsNeverRead() throws {
        let (catalog, _, _) = try setup()
        let folder = scratchFolder()
        catalog.choose(folder)
        catalog.foundTeam()
        try SharedMachine(
            author: "Mallory", machine: Machine(id: 1, name: "Evil", template: "x", spec: .team, state: .active),
            record: .init(), at: .now
        ).write(to: folder)
        catalog.refresh()
        #expect(catalog.teammates.isEmpty)
    }
}
