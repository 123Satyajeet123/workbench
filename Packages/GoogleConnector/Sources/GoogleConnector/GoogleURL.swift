import Foundation

enum GoogleURL {
    static func make(_ base: String, segments: [String], query: [URLQueryItem]) throws -> URL {
        var components = URLComponents(string: base)
        components?.percentEncodedPath += "/" + segments.map(encode).joined(separator: "/")
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { throw GoogleError.hostRefused(base) }
        return url
    }

    static func utc(_ date: Date) -> String {
        date.formatted(.iso8601)
    }

    private static func encode(_ segment: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        return segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? segment
    }
}

protocol PagedResponse: Decodable {
    associatedtype Item: Sendable
    var pageItems: [Item] { get }
    var nextPageToken: String? { get }
}

extension GoogleConnector {
    func allPages<Response: PagedResponse>(
        _ type: Response.Type, for email: String, url: (String?) throws -> URL
    ) async throws -> [Response.Item] {
        var items: [Response.Item] = []
        var pageToken: String?
        repeat {
            let page = try await getDecoded(try url(pageToken), for: email, as: Response.self)
            items += page.pageItems
            pageToken = page.nextPageToken
        } while pageToken != nil
        return items
    }
}
