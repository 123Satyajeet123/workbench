import Foundation
import GRDB
import Testing

@testable import WorkbenchCore

private let screenOn = CapturePolicy(switches: [.screen: true, .screenText: true])

private func page(_ document: String, text: String = "body", app: String = "Safari", bundleID: String = "b")
    -> ScreenSnapshot
{
    ScreenSnapshot(app: app, bundleID: bundleID, windowID: 1, document: document, title: "t", text: text)
}

struct GrantBindingTests {
    @Test func aBatchWithAnExpiredGrantIsRefusedAndOneWithALiveGrantIsKept() throws {
        var engine = CaptureEngine()
        let observed = engine.observe(page("example.com"), presence: .active, policy: screenOn, at: t0)
        let batch = try #require(observed)
        #expect(throws: StoreError.grantExpired) { try makeStore(clock: { t0 + 301 }).record(batch) }
        try makeStore(clock: { t0 + 299 }).record(batch)
    }
}

struct ForgetTests {
    private func store(keeping documents: [String]) throws -> Store {
        let store = try makeStore()
        var engine = CaptureEngine()
        for (index, document) in documents.enumerated() {
            var snapshot = page(document)
            snapshot.windowID = index
            let batch = engine.observe(snapshot, presence: .active, policy: screenOn, at: t0)
            try store.record(#require(batch))
        }
        return store
    }

    private func documents(_ store: Store) throws -> [String] {
        try store.queries.activities(since: day(-1)).filter { $0.kind == .window }.compactMap(\.document)
    }

    @Test func deletedTextIsNotLeftInTheDatabaseOrItsLog() throws {
        let store = try store(keeping: [])
        var engine = CaptureEngine()
        let secret = "SECRET-\(UUID().uuidString)"
        let batch = engine.observe(page("a.com", text: secret), presence: .active, policy: screenOn, at: t0)
        try store.record(#require(batch))
        func leaks() throws -> Bool {
            try ["workbench.sqlite", "workbench.sqlite-wal"].contains {
                let file = store.directory.appending(path: $0)
                return try Data(contentsOf: file).range(of: Data(secret.utf8)) != nil
            }
        }
        #expect(try leaks())
        try store.delete(.everything(before: nil))
        #expect(try !leaks())
    }

    @Test func aDeleteFailsWhileAnotherReaderHoldsTheLogAndSucceedsOnceItLetsGo() throws {
        let folder = temporaryDirectory()
        let store = try Store(directory: folder, clock: { t0 }, busyTimeout: 0.05)
        var engine = CaptureEngine()
        let secret = "SECRET-\(UUID().uuidString)"
        let batch = engine.observe(page("a.com", text: secret), presence: .active, policy: screenOn, at: t0)
        try store.record(#require(batch))

        var otherReader: DatabaseSnapshot? = try DatabasePool(path: folder.appending(path: "workbench.sqlite").path)
            .makeSnapshot()
        _ = try otherReader?.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM activity") }
        #expect(throws: StoreError.logNotTruncated) { try store.delete(.everything(before: nil)) }

        otherReader = nil
        try store.delete(.everything(before: nil))
        let log = try Data(contentsOf: folder.appending(path: "workbench.sqlite-wal"))
        #expect(log.range(of: Data(secret.utf8)) == nil)
    }
}
