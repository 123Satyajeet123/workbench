import Foundation
import Testing

@testable import GoogleConnector

struct DisconnectTests {
    @Test func aSavedSignInThatCannotBeReadIsStillDeletedAndTheFailureIsReturned() async throws {
        let keychain = GoogleKeychain(service: "com.hizen.workbench.google.test.\(UUID().uuidString)")
        let email = "ann@example.com"
        try keychain.save(Data("not an archive".utf8), account: email)
        let connector = makeConnector(recorder: Recorder(), keychain: keychain) { _ in Reply("{}") }
        let revoke = try await connector.disconnect(email)
        #expect(revoke != nil)
        #expect(try keychain.read(account: email) == nil)
    }

    @Test func anAccountThatIsNotThereIsReportedAndNothingIsLeft() async throws {
        let keychain = GoogleKeychain(service: "com.hizen.workbench.google.test.\(UUID().uuidString)")
        let connector = makeConnector(recorder: Recorder(), keychain: keychain) { _ in Reply("{}") }
        #expect(try await connector.disconnect("none@example.com") != nil)
        #expect(try keychain.accounts().isEmpty)
    }
}
