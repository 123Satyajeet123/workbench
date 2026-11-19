import Foundation
import Testing

@testable import GoogleConnector

struct KeychainTests {
    @Test func savesReadsListsAndDeletesPerAccount() throws {
        let keychain = GoogleKeychain(service: "com.hizen.workbench.google.test.\(UUID().uuidString)")
        try keychain.save(Data("one".utf8), account: "b@example.com")
        try keychain.save(Data("two".utf8), account: "a@example.com")
        try keychain.save(Data("three".utf8), account: "b@example.com")
        defer {
            try? keychain.delete(account: "a@example.com")
            try? keychain.delete(account: "b@example.com")
        }
        #expect(try keychain.read(account: "b@example.com") == Data("three".utf8))
        #expect(try keychain.accounts() == ["a@example.com", "b@example.com"])
        try keychain.delete(account: "a@example.com")
        #expect(try keychain.read(account: "a@example.com") == nil)
        #expect(try keychain.accounts() == ["b@example.com"])
    }

    @Test func emptyKeychainListsNothing() throws {
        #expect(try GoogleKeychain(service: "com.hizen.workbench.google.test.\(UUID().uuidString)").accounts().isEmpty)
    }

    @Test func serviceNameIsTheDocumentedOne() {
        #expect(GoogleKeychain().service == "com.hizen.workbench.google")
    }
}
