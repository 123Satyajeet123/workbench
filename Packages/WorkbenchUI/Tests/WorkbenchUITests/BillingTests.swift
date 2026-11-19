import Foundation
import Synchronization
import Testing
import WorkbenchCore

@testable import WorkbenchUI

private final class MemorySecrets: SecretStore, Sendable {
    let values = Mutex<[String: String]>([:])
    func read(_ name: String) -> String? { values.withLock { $0[name] } }
    func save(_ value: String, as name: String) throws { values.withLock { $0[name] = value } }
    func remove(_ name: String) throws { values.withLock { $0[name] = nil } }
}

@Suite struct BillingTests {
    @Test func theKeyLivesOnlyInTheSecretStoreAndTheBillingChoicePersists() throws {
        let store = try scratchStore()
        let secrets = MemorySecrets()
        let models = ModelSettings(store: store, secrets: secrets)
        #expect(models.billing == .plan && !models.hasAPIKey, "the sign-in by default")
        models.billing = .apiKey
        models.saveAPIKey("  sk-ant-mine  ")
        #expect(models.hasAPIKey && secrets.read(Billing.keyName) == "sk-ant-mine")
        #expect(try store.queries.state(forKey: "model.billing") == "apiKey")
        #expect(try store.queries.state(forKey: Billing.keyName) == nil, "never in the store")
        #expect(ModelSettings(store: store, secrets: secrets).billing == .apiKey)
        models.removeAPIKey()
        #expect(!models.hasAPIKey && secrets.read(Billing.keyName) == nil)
    }
}
