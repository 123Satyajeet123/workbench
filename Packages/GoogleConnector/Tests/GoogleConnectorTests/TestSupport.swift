import Foundation

@testable import GoogleConnector

actor Recorder {
    private(set) var requests: [URLRequest] = []
    private(set) var refreshFlags: [Bool] = []

    func record(_ request: URLRequest) { requests.append(request) }
    func record(forceRefresh: Bool) { refreshFlags.append(forceRefresh) }
}

struct StubTokens: GoogleAccessTokens {
    let recorder: Recorder
    var scopes = Set(GoogleEndpoint.calendarScopes + [GoogleEndpoint.gmailScope])

    func grantedScopes(for email: String) throws -> Set<String> { scopes }

    func accessToken(for email: String, forceRefresh: Bool) async throws -> String {
        await recorder.record(forceRefresh: forceRefresh)
        return forceRefresh ? "refreshed-token" : "first-token"
    }
}

struct Reply {
    let status: Int
    let body: String

    init(_ body: String, status: Int = 200) {
        self.status = status
        self.body = body
    }
}

func makeConnector(
    recorder: Recorder, scopes: Set<String>? = nil, keychain: GoogleKeychain? = nil,
    replies: @escaping @Sendable (URLRequest) -> Reply
) -> GoogleConnector {
    let http = GoogleHTTP { request in
        await recorder.record(request)
        let reply = replies(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: nil)!
        return (Data(reply.body.utf8), response)
    }
    let keychain = keychain ?? GoogleKeychain(service: "com.hizen.workbench.google.test")
    var tokens = StubTokens(recorder: recorder)
    if let scopes { tokens.scopes = scopes }
    return GoogleConnector(
        config: GoogleClientConfig(clientID: "id", clientSecret: "secret"), keychain: keychain,
        authorizer: GoogleAuthorizer(keychain: keychain), tokens: tokens, http: http)
}

func query(_ url: URL?, _ name: String) -> String? {
    URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
}
