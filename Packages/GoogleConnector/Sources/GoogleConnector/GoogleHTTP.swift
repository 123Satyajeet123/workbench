import Foundation

struct GoogleHTTP: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let transport: Transport

    init(transport: @escaping Transport = GoogleHTTP.live) {
        self.transport = transport
    }

    func send(_ request: URLRequest) async throws -> Data {
        guard let url = request.url else { throw GoogleError.hostRefused("") }
        try GoogleHostGuard.check(url)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch {
            throw GoogleError.transport(error.localizedDescription)
        }
        guard let status = (response as? HTTPURLResponse)?.statusCode else {
            throw GoogleError.transport("no HTTP answer")
        }
        guard (200..<300).contains(status) else {
            throw GoogleError.http(status: status, body: String(decoding: data.prefix(500), as: UTF8.self))
        }
        return data
    }

    static func get(_ url: URL, accessToken: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    static func form(_ url: URL, fields: [String: String]) -> URLRequest {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)
        return request
    }

    static let live: Transport = { request in
        try await session.data(for: request, delegate: RefuseRedirects())
    }

    private static let session = URLSession(configuration: .ephemeral)
}

private final class RefuseRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
