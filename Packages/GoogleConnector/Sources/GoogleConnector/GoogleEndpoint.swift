import AppAuth
import Foundation

enum GoogleEndpoint {
    static let authorization = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let token = URL(string: "https://oauth2.googleapis.com/token")!
    static let revoke = URL(string: "https://oauth2.googleapis.com/revoke")!

    static let calendarBase = "https://www.googleapis.com/calendar/v3"
    static let gmailBase = "https://gmail.googleapis.com/gmail/v1"

    static let calendarScopes = [
        "https://www.googleapis.com/auth/calendar.events.readonly",
        "https://www.googleapis.com/auth/calendar.calendarlist.readonly",
    ]

    static let gmailScope = "https://www.googleapis.com/auth/gmail.readonly"

    static let scopes = ["openid", "email"] + calendarScopes

    static var serviceConfiguration: OIDServiceConfiguration {
        OIDServiceConfiguration(authorizationEndpoint: authorization, tokenEndpoint: token)
    }
}

enum GoogleHostGuard {
    static let allowedHosts: Set<String> = [
        "accounts.google.com", "oauth2.googleapis.com", "www.googleapis.com", "gmail.googleapis.com",
    ]

    static func check(_ url: URL) throws {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil || url.port == 443,
            let host = url.host(percentEncoded: false)?.lowercased(), allowedHosts.contains(host)
        else { throw GoogleError.hostRefused(url.absoluteString) }
    }
}
