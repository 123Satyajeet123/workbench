import Foundation
import Synchronization
import Testing

@testable import WorkbenchCore

@Suite struct WebGateTests {
    private let hit = SearchHit(title: "t", url: URL(string: "https://news.example/a")!, snippet: "")

    @Test func withTheConsentOffNothingIsBuiltOrSent() throws {
        let store = try makeStore()
        var built = false
        #expect(throws: WebBlock.consentOff) {
            try WebSession.open(
                store: store, key: { _ in "key" },
                make: { _, _, _ in
                    built = true
                    return (FakeSearch(), FakePages())
                })
        }
        #expect(!built, "no provider is built without consent")
        try store.switchWeb(false)
        #expect(throws: WebBlock.consentOff) {
            try WebSession.fake(store: store, search: FakeSearch(), pages: FakePages())
        }
    }

    @Test func withTheCaptureModeOffNothingIsSentEvenWhenTheWebSwitchIsOn() throws {
        let store = try makeStore()
        try store.savePolicy(CapturePolicy(mode: .off, switches: [.web: true]))
        #expect(throws: WebBlock.consentOff) {
            try WebSession.fake(store: store, search: FakeSearch(), pages: FakePages())
        }
    }

    @Test func withNoKeyItStopsBeforeAnyCall() throws {
        let store = try makeStore()
        try store.switchWeb(true)
        let search = FakeSearch()
        #expect(throws: WebBlock.noKey) {
            try WebSession.fake(store: store, search: search, pages: FakePages(), key: nil)
        }
        #expect(throws: WebBlock.noKey) {
            try WebSession.fake(store: store, search: search, pages: FakePages(), key: "  ")
        }
        #expect(search.queries.withLock { $0 }.isEmpty)
    }

    @Test func withTheConsentOnAKeyAndRoomItSearchesAndCounts() async throws {
        let store = try makeStore()
        try store.switchWeb(true)
        try store.saveWebSettings(WebSettings(provider: .exa, monthlyCap: 2))
        let search = FakeSearch(hits: [hit])
        let session = try WebSession.fake(store: store, search: search, pages: FakePages())
        #expect(try await session.search("a", count: 5) == [hit])
        #expect(try store.queries.webQueriesSent(inMonthOf: t0) == 1)
    }

    @Test func theCapStopsTheSearchAndTheNextSessionAndSendsNothingMore() async throws {
        let store = try makeStore()
        try store.switchWeb(true)
        try store.saveWebSettings(WebSettings(monthlyCap: 2))
        let search = FakeSearch(hits: [hit])
        let session = try WebSession.fake(store: store, search: search, pages: FakePages())
        _ = try await session.search("a", count: 5)
        _ = try await session.search("b", count: 5)
        await #expect(throws: WebBlock.capReached(cap: 2)) { try await session.search("c", count: 5) }
        #expect(search.queries.withLock { $0 } == ["a", "b"], "the third query was never sent")
        #expect(throws: WebBlock.capReached(cap: 2)) {
            try WebSession.fake(store: store, search: search, pages: FakePages())
        }
    }

    @Test func theCapCountsPerCalendarMonth() async throws {
        let now = Mutex(t0)
        let store = try makeStore(clock: { now.withLock { $0 } })
        try store.switchWeb(true)
        try store.saveWebSettings(WebSettings(monthlyCap: 1))
        let search = FakeSearch()
        _ = try await WebSession.fake(store: store, search: search, pages: FakePages()).search("a", count: 1)
        now.withLock { $0 = day(40) }
        _ = try await WebSession.fake(store: store, search: search, pages: FakePages()).search("b", count: 1)
        #expect(search.queries.withLock { $0 } == ["a", "b"])
    }

    @Test func aSessionThatOutlivesItsGrantStops() async throws {
        let now = Mutex(t0)
        let store = try makeStore(clock: { now.withLock { $0 } })
        try store.switchWeb(true)
        let search = FakeSearch()
        let session = try WebSession.fake(store: store, search: search, pages: FakePages())
        now.withLock { $0 = t0.addingTimeInterval(CapturePolicy.grantLifetime + 1) }
        await #expect(throws: WebBlock.grantExpired) { try await session.search("a", count: 1) }
        await #expect(throws: WebBlock.grantExpired) { try await session.fetch(URL(string: "https://a.example/")!) }
        #expect(search.queries.withLock { $0 }.isEmpty)
    }
}
