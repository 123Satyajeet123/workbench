import Foundation

/// What the Claude command-line tool says about itself, read without a model call. A field is nil when the tool did not
/// say it: nil means not known, never a guess. The account's email and organisation are never read.
public struct ReaderStatus: Sendable, Equatable {
    public var installedAt: URL?
    public var version: String?
    public var signedIn: Bool?
    public var authMethod: String?
    public var subscriptionType: String?
    public var planTier: String?
    public var loginExpiresAt: Date?

    public init(
        installedAt: URL? = nil, version: String? = nil, signedIn: Bool? = nil, authMethod: String? = nil,
        subscriptionType: String? = nil, planTier: String? = nil, loginExpiresAt: Date? = nil
    ) {
        self.installedAt = installedAt
        self.version = version
        self.signedIn = signedIn
        self.authMethod = authMethod
        self.subscriptionType = subscriptionType
        self.planTier = planTier
        self.loginExpiresAt = loginExpiresAt
    }

    public static let notInstalled = ReaderStatus()

    /// The sign-in fields of the output of `claude auth status --json`. Output that is not a JSON object gives no field.
    public static func parse(authStatus json: Data, installedAt: URL?, version: String?) -> ReaderStatus {
        let fields = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] ?? [:]
        return ReaderStatus(
            installedAt: installedAt, version: version, signedIn: fields["loggedIn"] as? Bool,
            authMethod: fields["authMethod"] as? String, subscriptionType: fields["subscriptionType"] as? String,
            planTier: fields["planTier"] as? String, loginExpiresAt: moment(fields["loginExpiresAt"]))
    }

    /// The version number in the output of `claude --version`, such as "2.1.4 (Claude Code)".
    public static func version(from text: String) -> String? {
        text.firstMatch(of: #/\d+(\.\d+)+/#).map { String($0.output.0) }
    }

    private static func moment(_ value: Any?) -> Date? {
        if let text = value as? String { return try? Date(text, strategy: .iso8601) }
        guard let number = value as? Double else { return nil }
        return Date(timeIntervalSince1970: number > 100_000_000_000 ? number / 1000 : number)
    }
}
