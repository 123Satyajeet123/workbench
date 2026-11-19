import AppAuth
import Foundation
import Testing

@testable import GoogleConnector

struct AuthTests {
    @MainActor
    @Test func authorizationRequestCarriesPKCEStateScopesAndOfflineAccess() throws {
        let redirect = URL(string: "http://127.0.0.1:54321/")!
        let request = GoogleSignIn.authorizationRequest(
            config: GoogleClientConfig(clientID: "id", clientSecret: "secret"), redirect: redirect)
        let url = request.authorizationRequestURL()
        #expect(url.host() == "accounts.google.com")
        #expect(query(url, "code_challenge_method") == "S256")
        #expect(query(url, "code_challenge")?.isEmpty == false)
        #expect(query(url, "state")?.isEmpty == false)
        #expect(query(url, "access_type") == "offline")
        #expect(query(url, "prompt") == "consent")
        #expect(query(url, "include_granted_scopes") == "false")
        #expect(query(url, "redirect_uri") == "http://127.0.0.1:54321/")
        #expect(query(url, "scope") == GoogleEndpoint.scopes.joined(separator: " "))
        #expect(query(url, "client_secret") == nil)
        #expect(query(url, "login_hint") == nil)
    }

    @Test func signInAsksForTheCalendarOnlyAndNeverForMail() {
        #expect(
            GoogleEndpoint.scopes == [
                "openid", "email", "https://www.googleapis.com/auth/calendar.events.readonly",
                "https://www.googleapis.com/auth/calendar.calendarlist.readonly",
            ])
        #expect(!GoogleEndpoint.scopes.contains(GoogleEndpoint.gmailScope))
    }

    @MainActor
    @Test func theGmailRequestNamesTheAccountAndKeepsWhatWasGranted() {
        let request = GoogleSignIn.authorizationRequest(
            config: GoogleClientConfig(clientID: "id", clientSecret: "secret"),
            redirect: URL(string: "http://127.0.0.1:54321/")!, ask: .gmail(for: "ann@example.com"))
        let url = request.authorizationRequestURL()
        #expect(query(url, "scope") == GoogleEndpoint.gmailScope)
        #expect(query(url, "login_hint") == "ann@example.com")
        #expect(query(url, "include_granted_scopes") == "true")
        #expect(query(url, "access_type") == "offline")
    }

    @Test func aSignInAsAnotherAccountIsRefusedAndAMatchingOneIsAccepted() throws {
        let other = SignedInAccount(email: "bob@example.com", archivedState: Data())
        #expect(throws: GoogleError.signedInAsAnotherAccount(expected: "ann@example.com", got: "bob@example.com")) {
            try GoogleConnector.require(other, is: "ann@example.com")
        }
        try GoogleConnector.require(
            SignedInAccount(email: "ann@example.com", archivedState: Data()), is: "Ann@Example.com")
    }

    @Test func emptyClientSettingsMeanNotSetUp() {
        #expect(throws: GoogleError.notSetUp) { try GoogleClientConfig.from(info: [:]) }
        #expect(throws: GoogleError.notSetUp) {
            try GoogleClientConfig.from(info: ["GoogleClientID": "", "GoogleClientSecret": ""])
        }
        #expect(throws: GoogleError.notSetUp) { try GoogleClientConfig.from(info: ["GoogleClientID": "id"]) }
    }

    @Test func filledClientSettingsLoad() throws {
        let config = try GoogleClientConfig.from(info: ["GoogleClientID": "id", "GoogleClientSecret": "secret"])
        #expect(config.clientID == "id")
    }

    @Test func emailComesFromTheIDTokenClaim() throws {
        #expect(
            try IDTokenClaims.email(fromIDToken: jwt(#"{"email":"Ann@Example.com","sub":"1"}"#)) == "ann@example.com")
    }

    @Test func badIDTokensFailLoudly() {
        #expect(throws: GoogleError.missingEmail) { try IDTokenClaims.email(fromIDToken: jwt(#"{"sub":"1"}"#)) }
        #expect(throws: GoogleError.self) { try IDTokenClaims.email(fromIDToken: "not-a-jwt") }
        #expect(throws: GoogleError.self) { try IDTokenClaims.email(fromIDToken: jwt("not json")) }
    }

    private func jwt(_ claims: String) -> String {
        let payload = Data(claims.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "e30.\(payload).sig"
    }
}
