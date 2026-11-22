import Foundation
import Synchronization

@testable import WorkbenchCore

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

final class FakeSearch: SearchProvider, Sendable {
    let queries = Mutex<[String]>([])
    let hits: [SearchHit]

    init(hits: [SearchHit] = []) { self.hits = hits }

    func search(_ query: String, count: Int) async throws -> [SearchHit] {
        queries.withLock { $0.append(query) }
        return hits
    }
}

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
    static func fake(store: Store, search: FakeSearch, pages: FakePages, key: String? = "key") throws -> WebSession {
        try open(store: store, key: { _ in key }, make: { _, _, _ in (search, pages) })
    }
}

extension Store {
    func switchWeb(_ on: Bool) throws { try savePolicy(CapturePolicy(switches: [.web: on])) }
}
