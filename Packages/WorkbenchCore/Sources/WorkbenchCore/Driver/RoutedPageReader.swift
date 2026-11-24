import Foundation

/// Reads one page through the browser. `PageDriver` is the real one.
public protocol PageDriving: Sendable {
    func read(_ url: URL) async throws -> FetchedPage
}

extension PageDriver: PageDriving {}

/// How a page ended up read, or that it could not be.
public enum PageReadout: Sendable, Equatable {
    case fetched(FetchedPage)
    case browsed(FetchedPage)
    case couldNotRead(URL, DriverFailure)

    public var page: FetchedPage? {
        switch self {
        case .fetched(let page), .browsed(let page): page
        case .couldNotRead: nil
        }
    }
}

/// Read routing (ADR-018 Decision 3): the plain fetch first; the browser only when the fetch failed or gave too
/// little text. A page still unreadable after the browser ends as "could not read". It is never tried again. When the
/// browser was not used (none connected, the gate refused, a cap), the fetch result stands as it is, short or not.
public struct RoutedPageReader: Sendable {
    private let fetcher: any PageFetching
    private let driver: any PageDriving

    public init(fetcher: any PageFetching, driver: any PageDriving) {
        self.fetcher = fetcher
        self.driver = driver
    }

    public func read(_ url: URL) async -> PageReadout {
        let fetched = try? await fetcher.fetch(url)
        if let fetched, Self.isReadable(fetched) { return .fetched(fetched) }
        do {
            let page = try await driver.read(url)
            return Self.isReadable(page) ? .browsed(page) : .couldNotRead(url, .couldNotRead)
        } catch let failure as DriverFailure {
            if failure.browserWasNotUsed, let fetched { return .fetched(fetched) }
            return .couldNotRead(url, failure)
        } catch {
            return .couldNotRead(url, .couldNotRead)
        }
    }

    static func isReadable(_ page: FetchedPage) -> Bool {
        page.text.count >= RunSettings.standard.readablePageCharacters
    }
}
