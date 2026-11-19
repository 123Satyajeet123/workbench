import Foundation

struct GoogleClientConfig: Sendable {
    let clientID: String
    let clientSecret: String

    static func bundled(_ bundle: Bundle = .main) throws -> GoogleClientConfig {
        try from(info: bundle.infoDictionary ?? [:])
    }

    static func from(info: [String: Any]) throws -> GoogleClientConfig {
        let clientID = info["GoogleClientID"] as? String ?? ""
        let clientSecret = info["GoogleClientSecret"] as? String ?? ""
        guard !clientID.isEmpty, !clientSecret.isEmpty else { throw GoogleError.notSetUp }
        return GoogleClientConfig(clientID: clientID, clientSecret: clientSecret)
    }
}
