import Foundation
import Synchronization
import Testing

@testable import WorkbenchCore

/// Read routing: the plain fetch first, the browser only for a page the fetch could not read.
@Suite struct RoutedPageReaderTests {
    private final class Fetcher: PageFetching, Sendable {
        let result: Result<String, DriverFailure>
        let calls = Mutex(0)
        init(result: Result<String, DriverFailure>) { self.result = result }
        func fetch(_ url: URL) async throws -> FetchedPage {
            calls.withLock { $0 += 1 }
            return FetchedPage(url: url, text: try result.get())
        }
    }

    private final class Browser: PageDriving, Sendable {
        let result: Result<String, DriverFailure>
        let calls = Mutex(0)
        init(result: Result<String, DriverFailure>) { self.result = result }
        func read(_ url: URL) async throws -> FetchedPage {
            calls.withLock { $0 += 1 }
            return FetchedPage(url: url, text: try result.get())
        }
    }

    private let url = URL(string: "https://news.example.com/a")!
    private let enough = String(repeating: "x", count: RoutedPageReader.readableCharacters)
    private let tooShort = String(repeating: "x", count: RoutedPageReader.readableCharacters - 1)

    @Test func aPageTheFetchReadsIsNeverOpenedInTheBrowser() async {
        let (fetcher, browser) = (Fetcher(result: .success(enough)), Browser(result: .success(enough)))
        let readout = await RoutedPageReader(fetcher: fetcher, driver: browser).read(url)
        #expect(readout == .fetched(FetchedPage(url: url, text: enough)))
        #expect(browser.calls.withLock { $0 } == 0)
    }

    @Test func aShortPageIsOpenedInTheBrowser() async {
        let (fetcher, browser) = (Fetcher(result: .success(tooShort)), Browser(result: .success(enough)))
        let readout = await RoutedPageReader(fetcher: fetcher, driver: browser).read(url)
        #expect(readout == .browsed(FetchedPage(url: url, text: enough)))
        #expect(browser.calls.withLock { $0 } == 1)
    }

    @Test func aFailedFetchIsOpenedInTheBrowser() async {
        let (fetcher, browser) = (Fetcher(result: .failure(.timedOut)), Browser(result: .success(enough)))
        let readout = await RoutedPageReader(fetcher: fetcher, driver: browser).read(url)
        #expect(readout.page?.text == enough)
        #expect(browser.calls.withLock { $0 } == 1)
    }

    @Test func aPageStillShortAfterTheBrowserEndsAsCouldNotReadWithNoSecondTry() async {
        let (fetcher, browser) = (Fetcher(result: .success(tooShort)), Browser(result: .success(tooShort)))
        let readout = await RoutedPageReader(fetcher: fetcher, driver: browser).read(url)
        #expect(readout == .couldNotRead(url, .couldNotRead))
        #expect(fetcher.calls.withLock { $0 } == 1 && browser.calls.withLock { $0 } == 1, "never retried in a loop")
    }

    @Test func aFailedBrowserReadEndsAsCouldNotRead() async {
        let fetcher = Fetcher(result: .success("short"))
        for failure in [DriverFailure.timedOut, .connectionLost, .browser("unreadable")] {
            let browser = Browser(result: .failure(failure))
            #expect(await RoutedPageReader(fetcher: fetcher, driver: browser).read(url) == .couldNotRead(url, failure))
            #expect(browser.calls.withLock { $0 } == 1)
        }
    }

    @Test func whenTheBrowserWasNotUsedTheShortFetchResultStands() async {
        let fetcher = Fetcher(result: .success("short"))
        for failure in [DriverFailure.noBrowserConnected, .refused(.notWeb), .capReached(.pages(1))] {
            let readout = await RoutedPageReader(fetcher: fetcher, driver: Browser(result: .failure(failure))).read(url)
            #expect(readout == .fetched(FetchedPage(url: url, text: "short")))
        }
        let nothing = Fetcher(result: .failure(.timedOut))
        let browser = Browser(result: .failure(.noBrowserConnected))
        #expect(
            await RoutedPageReader(fetcher: nothing, driver: browser).read(url)
                == .couldNotRead(url, .noBrowserConnected))
    }
}
