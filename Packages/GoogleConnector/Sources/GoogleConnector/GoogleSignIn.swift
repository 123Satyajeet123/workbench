import AppAuth
import AppKit

struct SignedInAccount: Sendable {
    let email: String
    let archivedState: Data
}

@MainActor
enum GoogleSignIn {
    /// What one authorization asks for. A sign-in asks for the calendar. Gmail is a second request for the same account.
    enum Ask: Equatable {
        case signIn
        case gmail(for: String)

        var scopes: [String] {
            switch self {
            case .signIn: GoogleEndpoint.scopes
            case .gmail: [GoogleEndpoint.gmailScope]
            }
        }

        var requiredScopes: [String] {
            switch self {
            case .signIn: GoogleEndpoint.calendarScopes
            case .gmail: [GoogleEndpoint.gmailScope]
            }
        }

        var parameters: [String: String] {
            switch self {
            case .signIn:
                ["access_type": "offline", "prompt": "consent", "include_granted_scopes": "false"]
            case .gmail(let email):
                [
                    "access_type": "offline", "prompt": "consent", "include_granted_scopes": "true",
                    "login_hint": email,
                ]
            }
        }
    }

    static func authorizationRequest(config: GoogleClientConfig, redirect: URL, ask: Ask = .signIn)
        -> OIDAuthorizationRequest
    {
        OIDAuthorizationRequest(
            configuration: GoogleEndpoint.serviceConfiguration, clientId: config.clientID,
            clientSecret: config.clientSecret, scopes: ask.scopes, redirectURL: redirect,
            responseType: OIDResponseTypeCode, additionalParameters: ask.parameters)
    }

    static func run(config: GoogleClientConfig, ask: Ask = .signIn) async throws -> SignedInAccount {
        let listener = LoopbackListener()
        let request = authorizationRequest(config: config, redirect: try listener.start(), ask: ask)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                listener.handler.currentAuthorizationFlow = OIDAuthState.authState(
                    byPresenting: request, externalUserAgent: DefaultBrowserAgent()
                ) { state, error in
                    if let state {
                        continuation.resume(with: Result { try account(from: state, ask: ask) })
                    } else {
                        continuation.resume(
                            throwing: GoogleError.authorization(error?.localizedDescription ?? "no result"))
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in listener.handler.cancelHTTPListener() }
        }
    }

    private static func account(from state: OIDAuthState, ask: Ask) throws -> SignedInAccount {
        guard state.refreshToken != nil else { throw GoogleError.missingRefreshToken }
        guard let idToken = state.lastTokenResponse?.idToken else { throw GoogleError.missingEmail }
        let granted = Set((state.scope ?? "").split(separator: " ").map(String.init))
        let missing = ask.requiredScopes.filter { !granted.contains($0) }
        guard missing.isEmpty else { throw GoogleError.scopesNotGranted(missing) }
        let email = try IDTokenClaims.email(fromIDToken: idToken)
        return SignedInAccount(email: email, archivedState: try GoogleAuthorizer.archive(state))
    }
}

@MainActor
private final class LoopbackListener {
    let handler = OIDRedirectHTTPHandler(successURL: nil)

    func start() throws -> URL {
        var listenError: NSError?
        let redirect = handler.startHTTPListener(&listenError)
        if let listenError { throw GoogleError.authorization(listenError.localizedDescription) }
        return redirect
    }
}

private final class DefaultBrowserAgent: NSObject, OIDExternalUserAgent {
    func present(_ request: any OIDExternalUserAgentRequest, session: any OIDExternalUserAgentSession) -> Bool {
        NSWorkspace.shared.open(request.externalUserAgentRequestURL())
    }

    func dismiss(animated: Bool, completion: @escaping () -> Void) {
        completion()
    }
}
