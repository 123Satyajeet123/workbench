import AppAuth
import Foundation

protocol GoogleAccessTokens: Sendable {
    func accessToken(for email: String, forceRefresh: Bool) async throws -> String
    func grantedScopes(for email: String) throws -> Set<String>
}

actor GoogleAuthorizer: GoogleAccessTokens {
    private let keychain: GoogleKeychain

    init(keychain: GoogleKeychain) {
        self.keychain = keychain
    }

    func accessToken(for email: String, forceRefresh: Bool) async throws -> String {
        let state = try storedState(for: email)
        if forceRefresh { state.setNeedsTokenRefresh() }
        let token = try await freshAccessToken(of: state)
        try keychain.save(Self.archive(state), account: email)
        return token
    }

    nonisolated func grantedScopes(for email: String) throws -> Set<String> {
        Set((try Self.storedState(for: email, in: keychain).scope ?? "").split(separator: " ").map(String.init))
    }

    func refreshToken(for email: String) throws -> String {
        guard let token = try storedState(for: email).refreshToken else { throw GoogleError.missingRefreshToken }
        return token
    }

    private func storedState(for email: String) throws -> OIDAuthState {
        try Self.storedState(for: email, in: keychain)
    }

    private static func storedState(for email: String, in keychain: GoogleKeychain) throws -> OIDAuthState {
        guard let data = try keychain.read(account: email) else { throw GoogleError.notConnected(email: email) }
        guard let state = try NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: data) else {
            throw GoogleError.decoding("the saved sign-in for \(email)")
        }
        return state
    }

    static func archive(_ state: OIDAuthState) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: state, requiringSecureCoding: true)
    }

    private func freshAccessToken(of state: OIDAuthState) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            state.performAction { token, _, error in
                if let token {
                    continuation.resume(returning: token)
                } else {
                    continuation.resume(throwing: GoogleError.tokenRefresh(error?.localizedDescription ?? "no token"))
                }
            }
        }
    }
}
