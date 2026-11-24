import Foundation
import Testing
import WorkbenchCore

@testable import WebResearch

@Suite struct WebResearchTests {
    @Test func braveAsksForQueryAndCountWithTheKeyInItsHeader() throws {
        let request = BraveSearch.request(query: "Acme seed $11 Mn", count: 5, key: "k1")
        let url = try #require(request.url)
        let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(parts.host == "api.search.brave.com" && parts.path == "/res/v1/web/search")
        #expect(parts.queryItems?.first { $0.name == "q" }?.value == "Acme seed $11 Mn")
        #expect(parts.queryItems?.first { $0.name == "count" }?.value == "5")
        #expect(request.httpMethod == "GET" && request.value(forHTTPHeaderField: "X-Subscription-Token") == "k1")
        #expect(request.httpShouldHandleCookies == false)
    }

    @Test func exaPostsAJsonBodyWithTheKeyInItsHeader() throws {
        let request = try ExaSearch.request(query: "Acme seed", count: 4, key: "k2")
        #expect(request.url?.absoluteString == "https://api.exa.ai/search" && request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "k2")
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["query"] as? String == "Acme seed" && body["numResults"] as? Int == 4 && body["contents"] == nil)
    }

    @Test func repliesBecomeHits() throws {
        let brave = Data(
            #"{"web":{"results":[{"title":"A","url":"https://a.example/x","description":"d"},{"title":"B","url":"https://b.example/"}]}}"#
                .utf8)
        #expect(
            try BraveSearch.hits(in: brave).map(\.url.absoluteString) == ["https://a.example/x", "https://b.example/"])
        #expect(try BraveSearch.hits(in: Data("{}".utf8)).isEmpty)
        let exa = Data(#"{"results":[{"title":"A","url":"https://a.example/x","publishedDate":"2024-01-01"}]}"#.utf8)
        #expect(try ExaSearch.hits(in: exa).map(\.title) == ["A"])
    }

    @Test func onlyNamedHttpsHostsAreFetched() {
        let allowed = ["https://www.inc42.com/a", "https://news.example/b?x=1"]
        let refused = [
            "http://www.inc42.com/a", "https://localhost/a", "https://127.0.0.1/a", "https://192.168.1.5/a",
            "https://[::1]/a", "https://printer.local/a", "https://user:pw@news.example/a", "file:///etc/passwd",
            "https://intranet/a",
        ]
        #expect(allowed.allSatisfy { PageAddress.isFetchable(URL(string: $0)!) })
        #expect(refused.allSatisfy { !PageAddress.isFetchable(URL(string: $0)!) })
    }

    @Test func theTransportRefusesAGrantOfAnotherKindOrAnExpiredOne() async throws {
        let now = Date()
        let mail = CapturePolicy(switches: [.mail: true], allowList: [.mail: ["Deals"]])
        let other = try #require(mail.authorize(CaptureRequest(kind: .mail, label: "Deals"), at: now).grant)
        let request = BraveSearch.request(query: "q", count: 1, key: "k")
        await #expect(throws: WebBlock.grantExpired) {
            try await WebTransport(grant: other).send(request, limit: 10)
        }
        let web = try #require(
            CapturePolicy(switches: [.web: true]).authorize(
                CaptureRequest(kind: .web), at: now.addingTimeInterval(-RunSettings.standard.grantLifetimeSeconds - 5)
            ).grant)
        await #expect(throws: WebBlock.grantExpired) { try await WebTransport(grant: web).send(request, limit: 10) }
    }

    @Test func theFeedFetcherRefusesAnAddressItMayNotFetchBeforeItSends() async throws {
        let grant = try #require(
            CapturePolicy(switches: [.web: true]).authorize(CaptureRequest(kind: .web), at: Date()).grant)
        let fetcher = FeedFetcher(grant: grant)
        for address in [
            "http://news.example/feed", "https://127.0.0.1/feed", "https://printer.local/feed", "file:///etc/passwd",
        ] {
            let url = try #require(URL(string: address))
            await #expect(throws: FeedError.notAFeed(url)) { try await fetcher.fetch(url) }
        }
    }
}
