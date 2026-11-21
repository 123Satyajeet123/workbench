import CaptureService
import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

@Suite struct TeamTrustTests {
    private func catalog(_ name: String, secrets: SecretStore, folder: URL? = nil) throws -> TeamCatalogModel {
        let store = try scratchStore()
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { name }, notifier: FakeNotifier())
        let model = TeamCatalogModel(store: store, crew: crew, author: { name }, secrets: secrets)
        if let folder { model.choose(folder) }
        return model
    }

    @Test func theKeysLiveInTheSecretStoreAndTheSameFingerprintComesBack() throws {
        let secrets = MemorySecrets()
        let first = try catalog("Kabir", secrets: secrets).trust
        let again = try catalog("Kabir", secrets: secrets).trust
        #expect(first.fingerprint == again.fingerprint && first.fingerprint.split(separator: " ").count == 5)
        #expect(secrets.read("team.keys") != nil)
        #expect(try catalog("Asha", secrets: MemorySecrets()).trust.fingerprint != first.fingerprint)
    }

    @Test func aPersonCountsOnlyAfterTheFoundersConfirmationAndNothingReadsBefore() throws {
        let folder = scratchFolder()
        let kabir = try catalog("Kabir", secrets: MemorySecrets(), folder: folder)
        let asha = try catalog("Asha", secrets: MemorySecrets(), folder: folder)
        kabir.foundTeam()
        asha.refresh()
        #expect(asha.sync == nil && asha.trust.founder == nil, "Asha has not confirmed a founder")
        kabir.refresh()
        #expect(kabir.trust.waiting.map(\.subject) == ["Asha"] && kabir.trust.members.map(\.name) == ["Kabir"])

        formTeam(founder: kabir, others: [asha])
        #expect(kabir.trust.members.map(\.name) == ["Asha", "Kabir"] && kabir.trust.waiting.isEmpty)
        #expect(asha.trust.founder?.card == kabir.trust.card && asha.trust.isFounder == false)
    }

    @Test func envelopesThatFailTheChecksAreCountedForThePage() throws {
        let folder = scratchFolder()
        let kabir = try catalog("Kabir", secrets: MemorySecrets(), folder: folder)
        let asha = try catalog("Asha", secrets: MemorySecrets(), folder: folder)
        formTeam(founder: kabir, others: [asha])
        try FolderTransport(team: folder).put(Letter(kind: .envelope, id: "junk", body: Data("{}".utf8)))
        kabir.refresh()
        #expect(kabir.trust.unverified == 1)
        asha.refresh()
        #expect(asha.trust.unverified == 1)
    }
}
