import Foundation
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
        let observed = engine.observe(page("example.com"), idleSeconds: 0, policy: screenOn, at: t0)
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
            let batch = engine.observe(snapshot, idleSeconds: 0, policy: screenOn, at: t0)
            try store.record(#require(batch))
        }
        return store
    }

    private func documents(_ store: Store) throws -> [String] {
        try store.queries.activities(since: day(-1)).filter { $0.kind == .window }.compactMap(\.document)
    }

    @Test func aSiteIsForgottenWithItsSubdomainsAndALookalikeStays() throws {
        let store = try store(keeping: [
            "https://linkedin.com/in/a", "https://www.linkedin.com/feed", "https://notlinkedin.com/x",
        ])
        try store.delete(.activities(ActivityFilter(domain: "linkedin.com")))
        #expect(try documents(store) == ["https://notlinkedin.com/x"])
    }

    @Test func anAppAndATimeRangeAreForgottenAndTheRestStays() throws {
        let store = try store(keeping: ["a.com", "b.com"])
        try store.delete(.activities(ActivityFilter(bundleID: "other")))
        #expect(try documents(store).count == 2)
        try store.delete(.activities(ActivityFilter(from: day(1))))
        #expect(try documents(store).count == 2)
        try store.delete(.activities(ActivityFilter(from: day(-1), to: day(1))))
        #expect(try documents(store).isEmpty)
    }

    @Test func deletedTextIsNotLeftInTheDatabaseOrItsLog() throws {
        let store = try store(keeping: [])
        var engine = CaptureEngine()
        let secret = "SECRET-\(UUID().uuidString)"
        let batch = engine.observe(page("a.com", text: secret), idleSeconds: 0, policy: screenOn, at: t0)
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
}
