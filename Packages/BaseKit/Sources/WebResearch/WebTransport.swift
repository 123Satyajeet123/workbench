import Foundation
import WorkbenchCore

/// The only place Workbench opens a connection for web research. A request needs a live grant of the kind `web`, so
/// code that has no consent cannot send. No cookies, no cache, no credentials of the Mac.
struct WebTransport: Sendable {
    struct Failure: LocalizedError {
        let status: Int
        var errorDescription: String? { "The web request failed with status \(status)." }
    }

    let grant: CaptureGrant

    /// The body of a successful reply, cut at `limit` bytes, and its content type.
    func send(_ request: URLRequest, limit: Int) async throws -> (body: Data, contentType: String) {
        guard grant.kind == .web, grant.expiresAt > Date() else { throw WebBlock.grantExpired }
        let session = URLSession(configuration: .ephemeral, delegate: HTTPSRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw Failure(status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        var body = Data()
        for try await byte in bytes {
            body.append(byte)
            if body.count >= limit { break }
        }
        return (body, http.value(forHTTPHeaderField: "Content-Type") ?? "")
    }

    static func request(_ url: URL, method: String = "GET", headers: [String: String] = [:]) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = method
        request.httpShouldHandleCookies = false
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        return request
    }
}

/// A redirect is followed only to another https address that names a host, not a machine on this network.
private final class HTTPSRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        request.url.flatMap(PageAddress.isFetchable) == true ? request : nil
    }
}

enum PageAddress {
    /// Whether a page may be fetched: https, a named public host. Not an IP address, `localhost` or a `.local` name.
    static func isFetchable(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host()?.lowercased(), host.contains("."),
            url.user() == nil
        else { return false }
        let isAddress = host.allSatisfy { $0.isNumber || $0 == "." } || host.contains(":")
        return !isAddress && !host.hasSuffix(".local") && !host.hasSuffix(".internal") && host != "localhost"
    }
}
