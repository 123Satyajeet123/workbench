import Foundation

@testable import WorkbenchCore

/// The measurements of ADR-018 probes P0, P2 and P3, as pure functions. The live runs that feed them are in
/// `BrowserProbeLiveTests`; the founder runs those in his own browser.
enum DriverProbe {
    // MARK: P0: the worker stays alive with an idle port

    struct Sample: Sendable, Equatable {
        var minute: Int
        /// The browser answered a harmless command at this minute.
        var answered: Bool
        /// When the browser's connection opened, as the app saw it at this minute.
        var connectionOpened: Date?

    }

    /// Alive when every sample was answered on one and the same connection: a restarted worker opens a new one.
    static func workerStayedAlive(_ samples: [Sample]) -> Bool {
        !samples.isEmpty && samples.allSatisfy(\.answered) && Set(samples.compactMap(\.connectionOpened)).count == 1
            && samples.allSatisfy { $0.connectionOpened != nil }
    }

    // MARK: P2: a hidden tab loads its whole content

    struct Page: Sendable, Equatable {
        var name: String
        var url: URL
        /// Text that only appears when the whole page loaded: below the fold, or drawn by the page's own script.
        var marker: String
    }

    /// Public pages chosen by hand, not yet checked in a browser. A lazy page, a script-drawn page, a static page.
    static let p2Pages = [
        Page(
            name: "lazy", url: URL(string: "https://infinite-scroll.com/demo/full-page/")!, marker: "five page spread"),
        Page(name: "script-drawn", url: URL(string: "https://todomvc.com/examples/react/dist/")!, marker: "todos"),
        Page(name: "static", url: URL(string: "https://example.com/")!, marker: "Example Domain"),
    ]

    struct PageResult: Sendable, Equatable {
        var name: String
        var characters: Int
        var markerFound: Bool
        var failure: String?
    }

    static func result(of page: Page, _ outcome: Result<FetchedPage, DriverFailure>) -> PageResult {
        switch outcome {
        case .success(let read):
            PageResult(
                name: page.name, characters: read.text.count, markerFound: fold(read.text).contains(fold(page.marker)))
        case .failure(let failure):
            PageResult(name: page.name, characters: 0, markerFound: false, failure: "\(failure)")
        }
    }

    // MARK: P3: read recall of the pages a plain fetch could not read

    struct Claim: Decodable, Sendable {
        var id: String
        var company: String
        var trueValue: String

        private enum CodingKeys: String, CodingKey {
            case id, company
            case trueValue = "true_value"
        }
    }

    struct SearchResult: Decodable, Sendable {
        var id: String
        var results: [Hit]

        struct Hit: Decodable, Sendable { var url: String }
    }

    struct Recall: Sendable, Equatable {
        var pages: Int
        var plainUnreadable: Int
        var browserReadable: Int
        var claims: Int
        var claimsWithValueFromFetch: Int
        var claimsWithValueAfterBrowser: Int
    }

    /// `fetched` and `browsed` map a result address to its text; a page the browser did not read is missing from
    /// `browsed`. The value counts as found on a page that holds the true value and the company name.
    static func recall(
        claims: [Claim], results: [SearchResult], fetched: [String: String], browsed: [String: String]
    ) -> Recall {
        let addresses = Set(results.flatMap { $0.results.map(\.url) })
        let unreadable = addresses.filter { (fetched[$0] ?? "").count < RunSettings.standard.readablePageCharacters }
        let readable = unreadable.filter { (browsed[$0] ?? "").count >= RunSettings.standard.readablePageCharacters }
        func holdsValue(_ claim: Claim, in texts: [String]) -> Bool {
            texts.contains { fold($0).contains(fold(claim.trueValue)) && fold($0).contains(fold(claim.company)) }
        }
        let byClaim = Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0.results.map(\.url)) })
        var fromFetch = 0
        var afterBrowser = 0
        for claim in claims {
            let pages = byClaim[claim.id] ?? []
            let fetchedTexts = pages.compactMap { fetched[$0] }
            if holdsValue(claim, in: fetchedTexts) { fromFetch += 1 }
            if holdsValue(claim, in: fetchedTexts + pages.compactMap { browsed[$0] }) { afterBrowser += 1 }
        }
        return Recall(
            pages: addresses.count, plainUnreadable: unreadable.count, browserReadable: readable.count,
            claims: claims.count, claimsWithValueFromFetch: fromFetch, claimsWithValueAfterBrowser: afterBrowser)
    }

    static func fold(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping.replacingOccurrences(of: "’", with: "'").lowercased()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
