import Foundation
import Testing

@testable import WorkbenchCore

/// The page reading of a web session: the fetch first, the person's browser only for what the fetch could not read.
@Suite struct SessionPageReadingTests {
    private let short = URL(string: "https://app.example.com/round")!
    private let long = URL(string: "https://news.example.com/round")!
    private let enough = String(repeating: "Acme raised money. ", count: 40)

    private func session(browser: any DriverTransport, store: Store) throws -> (WebSession, FakePages) {
        try store.switchWeb(true)
        let pages = FakePages([short.absoluteString: "loading...", long.absoluteString: enough])
        return (try WebSession.fake(store: store, search: FakeSearch(), pages: pages, browser: browser), pages)
    }

    @Test func aShortFetchedPageIsReadByTheBrowserAndLoggedUnderTheRun() async throws {
        let store = try makeStore()
        let browser = FakeBrowser()
        browser.serve(short.absoluteString, text: enough + "from the browser")
        let (session, _) = try session(browser: browser, store: store)
        let read = try await session.readPages([short, long])
        #expect(read.map(\.text) == [enough + "from the browser", enough])
        #expect(browser.opens == [short], "the page the fetch read was never opened")
        #expect(browser.closeAllCount == 1)
        let rows = try store.queries.driverLog(runID: session.runID)
        #expect(rows.map(\.command) == ["open", "read", "close_all"])
        #expect(rows.allSatisfy { $0.runID == session.runID })
    }

    @Test func withNoBrowserTheFetchResultIsKeptAndNothingWaits() async throws {
        let store = try makeStore()
        let (session, _) = try session(browser: NoBrowser(), store: store)
        let read = try await session.readPages([short, long])
        #expect(read.map(\.text) == ["loading...", enough])
        #expect(try store.queries.driverLog(runID: session.runID).filter { $0.command != "close_all" }.count == 1)
    }

    @Test func aPageThatStaysShortAfterTheBrowserIsLeftOut() async throws {
        let store = try makeStore()
        let browser = FakeBrowser()
        browser.serve(short.absoluteString, text: "still loading")
        let (session, _) = try session(browser: browser, store: store)
        #expect(try await session.readPages([short]).isEmpty)
        #expect(browser.opens.count == 1, "not tried again")
    }

    @Test func theConsentSwitchIsTheGateForTheBrowserToo() async throws {
        let store = try makeStore()
        let browser = FakeBrowser()
        try store.switchWeb(false)
        #expect(throws: WebBlock.consentOff) {
            try WebSession.fake(store: store, search: FakeSearch(), pages: FakePages(), browser: browser)
        }
        #expect(browser.sent.isEmpty)
    }

    @Test func aSiteTheCaptureRulesDenyIsNeverOpenedInTheBrowser() async throws {
        let store = try makeStore()
        let browser = FakeBrowser()
        let bank = URL(string: "https://hdfcbank.com/news")!
        try store.switchWeb(true)
        let session = try WebSession.fake(
            store: store, search: FakeSearch(), pages: FakePages([bank.absoluteString: "short"]), browser: browser)
        #expect(try await session.readPages([bank]).map(\.text) == ["short"], "the fetch result stands")
        #expect(browser.sent.isEmpty)
    }
}
