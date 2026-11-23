import Foundation
import WorkbenchCore

/// Brave Search API: GET /res/v1/web/search?q=&count=, key in `X-Subscription-Token`, results in `web.results`
/// (Brave documentation, Web Search, Get started).
public struct BraveSearch: SearchProvider {
    static let host = "api.search.brave.com"
    let transport: WebTransport
    let key: String

    public init(key: String, grant: CaptureGrant) {
        self.key = key
        transport = WebTransport(grant: grant)
    }

    static func request(query: String, count: Int, key: String) -> URLRequest {
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = host
        parts.path = "/res/v1/web/search"
        parts.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "count", value: String(count))]
        return WebTransport.request(
            parts.url!, headers: ["X-Subscription-Token": key, "Accept": "application/json"])
    }

    static func hits(in data: Data) throws -> [SearchHit] {
        struct Reply: Decodable {
            struct Web: Decodable {
                struct Result: Decodable {
                    var title: String
                    var url: URL
                    var description: String?
                }
                var results: [Result]
            }
            var web: Web?
        }
        return try JSONDecoder().decode(Reply.self, from: data).web?.results.map {
            SearchHit(title: $0.title, url: $0.url, snippet: $0.description ?? "")
        } ?? []
    }

    public func search(_ query: String, count: Int) async throws -> [SearchHit] {
        let reply = try await transport.send(Self.request(query: query, count: count, key: key), limit: 2_000_000)
        return try Self.hits(in: reply.body)
    }
}

/// Exa Search API: POST /search with `{query, numResults, type}`, key in `x-api-key`, results in `results`
/// (Exa documentation, API reference, Search). No `contents` is asked for: pages are fetched by Workbench itself.
public struct ExaSearch: SearchProvider {
    static let host = "api.exa.ai"
    let transport: WebTransport
    let key: String

    public init(key: String, grant: CaptureGrant) {
        self.key = key
        transport = WebTransport(grant: grant)
    }

    static func request(query: String, count: Int, key: String) throws -> URLRequest {
        var request = WebTransport.request(
            URL(string: "https://\(host)/search")!, method: "POST",
            headers: ["x-api-key": key, "Content-Type": "application/json", "Accept": "application/json"])
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["query": query, "numResults": count, "type": "auto"] as [String: Any])
        return request
    }

    static func hits(in data: Data) throws -> [SearchHit] {
        struct Reply: Decodable {
            struct Result: Decodable {
                var title: String?
                var url: URL
            }
            var results: [Result]
        }
        return try JSONDecoder().decode(Reply.self, from: data).results.map {
            SearchHit(title: $0.title ?? "", url: $0.url, snippet: "")
        }
    }

    public func search(_ query: String, count: Int) async throws -> [SearchHit] {
        let reply = try await transport.send(try Self.request(query: query, count: count, key: key), limit: 2_000_000)
        return try Self.hits(in: reply.body)
    }
}

/// Fetches a page and returns its text. Only https pages on named hosts; only HTML and plain text; at most 1.5 MB.
public struct WebPageFetcher: PageFetching {
    static let byteLimit = 1_500_000
    let transport: WebTransport

    public init(grant: CaptureGrant) {
        transport = WebTransport(grant: grant)
    }

    public func fetch(_ url: URL) async throws -> FetchedPage {
        guard PageAddress.isFetchable(url) else { throw WebTransport.Failure(status: 0) }
        let reply = try await transport.send(
            WebTransport.request(url, headers: ["Accept": "text/html, text/plain"]), limit: Self.byteLimit)
        let kind = reply.contentType.lowercased()
        guard kind.contains("text/html") || kind.contains("text/plain") else { throw WebTransport.Failure(status: 415) }
        let text = String(decoding: reply.body, as: UTF8.self)
        return FetchedPage(url: url, text: kind.contains("html") ? HTMLText.plain(text) : text)
    }
}

/// The provider and the fetcher for a session, built from a grant the consent gate gave. `modelSearch` is the
/// provider for `.model`, which needs no key.
public func makeWebSession(
    provider: SearchProviderKind, key: String, grant: CaptureGrant, modelSearch: ModelSearch
) -> (any SearchProvider, any PageFetching) {
    switch provider {
    case .model: (modelSearch, WebPageFetcher(grant: grant))
    case .brave: (BraveSearch(key: key, grant: grant), WebPageFetcher(grant: grant))
    case .exa: (ExaSearch(key: key, grant: grant), WebPageFetcher(grant: grant))
    }
}
