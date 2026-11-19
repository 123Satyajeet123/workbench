import Foundation

public enum GoogleError: Error, Equatable, Sendable {
    case notSetUp
    case notConnected(email: String)
    case hostRefused(String)
    case transport(String)
    case http(status: Int, body: String)
    case decoding(String)
    case authorization(String)
    case missingRefreshToken
    case missingEmail
    case scopesNotGranted([String])
    case tokenRefresh(String)
    case unauthorized(email: String)
    case keychain(status: Int32)
    case messageOutsideWorkbenchLabel(id: String)
    case invalidMessageID(String)
    case revoke(String)
    case gmailNotEnabled(email: String)
    case signedInAsAnotherAccount(expected: String, got: String)
}

extension GoogleError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notSetUp: "Google is not set up in this build."
        case .notConnected(let email): "\(email) is not connected."
        case .hostRefused(let url): "Workbench refused to contact \(url)."
        case .transport(let reason): "Workbench could not reach Google: \(reason)"
        case .http(let status, _): "Google answered with error \(status)."
        case .decoding(let reason): "Workbench could not read Google's answer: \(reason)"
        case .authorization(let reason): "Google sign-in did not finish: \(reason)"
        case .missingRefreshToken: "Google did not give a long-lived sign-in. Try again."
        case .missingEmail: "Google did not say which account signed in. Try again."
        case .scopesNotGranted(let scopes):
            "You did not allow everything Workbench asks for (\(scopes.count) missing). Try again and allow all."
        case .tokenRefresh(let reason): "Google refused to renew the sign-in: \(reason)"
        case .unauthorized(let email): "Google no longer accepts the sign-in for \(email). Connect it again."
        case .keychain(let status): "The Mac Keychain refused the request (code \(status))."
        case .messageOutsideWorkbenchLabel: "That message does not have the Gmail label Workbench."
        case .invalidMessageID: "That message id is not valid."
        case .gmailNotEnabled(let email):
            "Workbench may not read the mail of \(email) yet. Turn on “Read my Workbench label” in Settings > Accounts."
        case .signedInAsAnotherAccount(let expected, let got):
            "You signed in as \(got), but this step is for \(expected). Nothing changed. Try again with \(expected)."
        case .revoke(let reason):
            "Workbench removed the account from this Mac. Google did not confirm the disconnect: \(reason)"
        }
    }
}
