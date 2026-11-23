import Foundation
import WorkbenchCore

/// Fetches a news feed. Only an https address of a named public host, only XML, at most 3 MB. Which feeds may be
/// fetched is `FeedSession`'s check. It sends through `WebTransport`, so it needs a live grant of the kind `web`.
public struct FeedFetcher: FeedFetching {
    static let byteLimit = 3_000_000
    let transport: WebTransport

    public init(grant: CaptureGrant) {
        transport = WebTransport(grant: grant)
    }

    public func fetch(_ url: URL) async throws -> Data {
        guard PageAddress.isFetchable(url) else { throw FeedError.notAFeed(url) }
        let reply = try await transport.send(
            WebTransport.request(url, headers: ["Accept": "application/rss+xml, application/atom+xml, text/xml"]),
            limit: Self.byteLimit)
        guard reply.contentType.lowercased().contains("xml") else { throw WebTransport.Failure(status: 415) }
        return reply.body
    }
}
