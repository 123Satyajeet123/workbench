import Foundation

public struct GoogleConnector: Sendable {
    private let config: GoogleClientConfig
    private let keychain: GoogleKeychain
    private let authorizer: GoogleAuthorizer
    let tokens: any GoogleAccessTokens
    let http: GoogleHTTP

    public init(bundle: Bundle = .main) throws {
        let keychain = GoogleKeychain()
        let authorizer = GoogleAuthorizer(keychain: keychain)
        self.init(
            config: try GoogleClientConfig.bundled(bundle), keychain: keychain, authorizer: authorizer,
            tokens: authorizer, http: GoogleHTTP())
    }

    init(
        config: GoogleClientConfig, keychain: GoogleKeychain, authorizer: GoogleAuthorizer,
        tokens: any GoogleAccessTokens, http: GoogleHTTP
    ) {
        self.config = config
        self.keychain = keychain
        self.authorizer = authorizer
        self.tokens = tokens
        self.http = http
    }

    public func accounts() throws -> [String] {
        try keychain.accounts()
    }

    @MainActor
    public func connect() async throws -> String {
        let account = try await GoogleSignIn.run(config: config)
        try keychain.save(account.archivedState, account: account.email)
        return account.email
    }

    public func gmailEnabled(for email: String) throws -> Bool {
        try tokens.grantedScopes(for: email).contains(GoogleEndpoint.gmailScope)
    }

    /// A second authorization for the same account. A sign-in as another account changes nothing.
    @MainActor
    public func enableWorkbenchLabel(for email: String) async throws {
        let account = try await GoogleSignIn.run(config: config, ask: .gmail(for: email))
        try Self.require(account, is: email)
        try keychain.save(account.archivedState, account: email)
    }

    static func require(_ account: SignedInAccount, is email: String) throws {
        guard account.email.lowercased() == email.lowercased() else {
            throw GoogleError.signedInAsAnotherAccount(expected: email, got: account.email)
        }
    }

    func requireGmail(for email: String) throws {
        guard try gmailEnabled(for: email) else { throw GoogleError.gmailNotEnabled(email: email) }
    }

    /// Returns the revoke error when Google did not confirm. The local sign-in is deleted either way.
    public func disconnect(_ email: String) async throws -> GoogleError? {
        var revokeError: GoogleError?
        do {
            let token = try await authorizer.refreshToken(for: email)
            _ = try await http.send(GoogleHTTP.form(GoogleEndpoint.revoke, fields: ["token": token]))
        } catch {
            revokeError = .revoke(error.localizedDescription)
        }
        try keychain.delete(account: email)
        return revokeError
    }

    func get(_ url: URL, for email: String) async throws -> Data {
        do {
            return try await send(url, for: email, forceRefresh: false)
        } catch GoogleError.http(status: 401, body: _) {
            do {
                return try await send(url, for: email, forceRefresh: true)
            } catch GoogleError.http(status: 401, body: _) {
                throw GoogleError.unauthorized(email: email)
            }
        }
    }

    func getDecoded<Value: Decodable>(_ url: URL, for email: String, as type: Value.Type) async throws -> Value {
        let data = try await get(url, for: email)
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            throw GoogleError.decoding("\(Value.self): \(error)")
        }
    }

    private func send(_ url: URL, for email: String, forceRefresh: Bool) async throws -> Data {
        let token = try await tokens.accessToken(for: email, forceRefresh: forceRefresh)
        return try await http.send(GoogleHTTP.get(url, accessToken: token))
    }
}
