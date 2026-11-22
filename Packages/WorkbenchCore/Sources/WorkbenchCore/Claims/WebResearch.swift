import Foundation

public enum SearchProviderKind: String, Codable, CaseIterable, Sendable {
    case brave, exa

    public var title: String {
        switch self {
        case .brave: "Brave Search"
        case .exa: "Exa"
        }
    }

    public var host: String {
        switch self {
        case .brave: "api.search.brave.com"
        case .exa: "api.exa.ai"
        }
    }

    public var keyName: String { "web-search-\(rawValue)" }
}

public struct SearchHit: Sendable, Equatable {
    public var title: String
    public var url: URL
    public var snippet: String

    public init(title: String, url: URL, snippet: String) {
        self.title = title
        self.url = url
        self.snippet = snippet
    }
}

public struct FetchedPage: Sendable, Equatable {
    public var url: URL
    public var text: String

    public init(url: URL, text: String) {
        self.url = url
        self.text = text
    }
}

public protocol SearchProvider: Sendable {
    func search(_ query: String, count: Int) async throws -> [SearchHit]
}

public protocol PageFetching: Sendable {
    func fetch(_ url: URL) async throws -> FetchedPage
}

public struct WebSettings: Codable, Sendable, Equatable {
    public var provider: SearchProviderKind
    public var monthlyCap: Int

    public init(provider: SearchProviderKind = .brave, monthlyCap: Int = 100) {
        self.provider = provider
        self.monthlyCap = monthlyCap
    }
}
