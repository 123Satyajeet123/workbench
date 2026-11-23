import Foundation

/// The search services Workbench can send a query to. `model` is the Claude CLI's own web search and needs no key;
/// the others need the key the founder gives.
public enum SearchProviderKind: String, Codable, CaseIterable, Sendable {
    case model, brave, exa

    public var title: String {
        switch self {
        case .model: "Claude web search, no key"
        case .brave: "Brave Search"
        case .exa: "Exa"
        }
    }

    public var needsKey: Bool { self != .model }

    /// The name of the key in the Keychain.
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

/// A page as fetched: its address and its text, as plain text.
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

/// The founder's choices for web research. The switch itself is the consent kind `web`.
public struct WebSettings: Codable, Sendable, Equatable {
    public var provider: SearchProviderKind
    /// The most queries sent in one calendar month.
    public var monthlyCap: Int

    public init(provider: SearchProviderKind = .model, monthlyCap: Int = 100) {
        self.provider = provider
        self.monthlyCap = monthlyCap
    }
}
