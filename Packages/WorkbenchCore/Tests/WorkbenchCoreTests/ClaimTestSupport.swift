import Foundation
import Synchronization

@testable import WorkbenchCore

/// The claim types the built-in deal intake machine lists.
let fundClaimTypes = MachineTemplate.dealIntake.spec.claimTypes!

/// Answers each call with the next reply in the list, and remembers each input.
final class SequencedModel: StructuredModel, Sendable {
    let name = "sequenced"
    private let replies: Mutex<[String]>
    let inputs = Mutex<[String]>([])

    init(_ replies: [String]) { self.replies = Mutex(replies) }

    func generate<T: Decodable & Sendable>(_ type: T.Type, schema: JSONSchema, instructions: String, input: String)
        async throws -> ModelAnswer<T>
    {
        inputs.withLock { $0.append(input) }
        let text = replies.withLock { $0.isEmpty ? "{}" : $0.removeFirst() }
        return ModelAnswer(
            value: try JSONDecoder().decode(T.self, from: Data(text.utf8)), model: "sequenced-1", usage: Usage(),
            reply: text)
    }
}

/// A search provider that records every query and answers with fixed hits.
final class FakeSearch: SearchProvider, Sendable {
    let queries = Mutex<[String]>([])
    let hits: [SearchHit]

    init(hits: [SearchHit] = []) { self.hits = hits }

    func search(_ query: String, count: Int) async throws -> [SearchHit] {
        queries.withLock { $0.append(query) }
        return hits
    }
}

/// A fetcher that records every address and answers from a table of pages.
final class FakePages: PageFetching, Sendable {
    let fetched = Mutex<[URL]>([])
    let pages: [URL: String]

    init(_ pages: [String: String] = [:]) {
        self.pages = Dictionary(uniqueKeysWithValues: pages.map { (URL(string: $0.key)!, $0.value) })
    }

    func fetch(_ url: URL) async throws -> FetchedPage {
        fetched.withLock { $0.append(url) }
        return FetchedPage(url: url, text: pages[url] ?? "")
    }
}

extension WebSession {
    /// A session over fakes, opened through the real gate.
    static func fake(
        store: Store, search: FakeSearch, pages: FakePages, key: String? = "key",
        browser: any DriverTransport = NoBrowser()
    ) throws -> WebSession {
        try open(store: store, key: { _ in key }, browser: browser, make: { _, _, _ in (search, pages) })
    }
}

extension Store {
    func switchWeb(_ on: Bool) throws { try savePolicy(CapturePolicy(switches: [.web: on])) }
}
