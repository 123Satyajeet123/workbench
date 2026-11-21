import Foundation
import Testing

@testable import WorkbenchCore

/// Old plaintext files become envelopes, sent by their author's own app.
@Suite struct SyncMigrationTests {
    private let machine = Machine(id: 1, name: "Pip", template: "team.ledger", spec: .team, state: .active)

    private func legacyFolder(for team: Cluster) throws -> URL {
        let folder = team.founder.team
        try writeLegacyLog(
            [workEvent("e1", by: "Kabir", clock: 1, text: "plain note"), workEvent("a1", by: "Asha", clock: 2)],
            author: "Kabir", to: folder)
        try SharedMachine(author: "Kabir", machine: machine, record: .init(), at: t0).write(to: folder)
        try SharedDay(
            author: "Kabir", machine: machine, day: WorkDay(containing: t0), items: [], audience: ["Kabir", "Asha"],
            at: t0
        ).write(to: folder)
        try SharedMachine(author: "Asha", machine: machine, record: .init(), at: t0).write(to: folder)
        return folder
    }

    @Test func aPersonsOwnFilesBecomeEnvelopesAreRemovedAndOthersFilesAreLeftAlone() throws {
        let team = try Cluster.formed(["Kabir", "Asha"])
        let folder = try legacyFolder(for: team)
        let sent = try PlaintextMigration.run(team: folder, sync: team.sync(team.founder))
        #expect(sent == 3, "Kabir's event, machine and day; not Asha's event or machine")

        let seen = try team.sync(team.founder).receive()
        #expect(seen.events.map(\.id) == ["e1"] && seen.machines.map(\.author) == ["Kabir"] && seen.days.count == 1)
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "events/Kabir.jsonl").path))
        #expect(SharedMachine.read(from: folder).files.map(\.author) == ["Asha"], "Asha's own app moves hers")
        #expect(SharedDay.read(from: folder).files.isEmpty)
        #expect(
            try PlaintextMigration.run(team: folder, sync: team.sync(team.founder)) == 0, "a second run does nothing")
    }

    @Test func aFileWhoseReadersHaveNoConfirmedKeyStaysUntilTheyDo() throws {
        let team = try Cluster.formed(["Kabir", "Asha"])
        let folder = team.founder.team
        try SharedDay(
            author: "Kabir", machine: machine, day: WorkDay(containing: t0), items: [], audience: ["Kabir", "Dev"],
            at: t0
        ).write(to: folder)
        try PlaintextMigration.run(team: folder, sync: team.sync(team.founder))
        #expect(SharedDay.read(from: folder).files.count == 1, "Dev is not confirmed, so the plaintext waits")
        #expect(try team.sync(team.founder).receive().days.isEmpty)
    }
}
