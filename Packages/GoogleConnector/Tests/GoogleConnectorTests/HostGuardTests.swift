import Foundation
import Testing

@testable import GoogleConnector

struct HostGuardTests {
    @Test(arguments: [
        "https://accounts.google.com/o/oauth2/v2/auth", "https://oauth2.googleapis.com/token",
        "https://www.googleapis.com/calendar/v3/users/me/calendarList",
        "https://gmail.googleapis.com/gmail/v1/users/me/labels",
    ])
    func allowedHostsPass(_ url: String) throws {
        try GoogleHostGuard.check(URL(string: url)!)
    }

    @Test(arguments: [
        "http://www.googleapis.com/calendar/v3", "https://evil.example.com/token",
        "https://www.googleapis.com.evil.example.com/x", "https://accounts.google.com@evil.example.com/x",
        "https://www.googleapis.com:8443/x", "https://drive.googleapis.com/drive/v3/files", "file:///etc/passwd",
    ])
    func otherHostsAreRefused(_ url: String) {
        #expect(throws: GoogleError.hostRefused(url)) { try GoogleHostGuard.check(URL(string: url)!) }
    }

    @Test func seamRefusesBeforeTheTransportRuns() async {
        let recorder = Recorder()
        let http = GoogleHTTP { request in
            await recorder.record(request)
            return (Data(), URLResponse())
        }
        await #expect(throws: GoogleError.hostRefused("https://evil.example.com/x")) {
            _ = try await http.send(URLRequest(url: URL(string: "https://evil.example.com/x")!))
        }
        #expect(await recorder.requests.isEmpty)
    }

    @Test func seamPassesAnAllowedHostAndMapsErrors() async throws {
        let ok = GoogleHTTP { request in
            (
                Data("fine".utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }
        let url = URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!
        #expect(try await ok.send(URLRequest(url: url)) == Data("fine".utf8))

        let denied = GoogleHTTP { request in
            (Data("no".utf8), HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!)
        }
        await #expect(throws: GoogleError.http(status: 403, body: "no")) {
            _ = try await denied.send(URLRequest(url: url))
        }

        let offline = GoogleHTTP { _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: GoogleError.self) { _ = try await offline.send(URLRequest(url: url)) }
    }
}
