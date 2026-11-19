import Foundation
import Testing

@testable import GoogleConnector

struct CalendarTests {
    private static let calendars =
        #"{"items":[{"id":"ann@example.com","summary":"Ann","primary":true,"accessRole":"owner"}]}"#
    private static let events = """
        {"items":[{"id":"e1","status":"confirmed","summary":"Founder call","start":{"dateTime":"2026-11-17T10:00:00+05:30"},
        "end":{"dateTime":"2026-11-17T10:30:00+05:30"},"organizer":{"email":"ann@example.com","self":true},
        "attendees":[{"email":"founder@example.com","responseStatus":"accepted"},{"email":"ann@example.com","self":true}],
        "hangoutLink":"https://meet.google.com/abc","conferenceData":{"entryPoints":[{"entryPointType":"video","uri":"https://meet.google.com/abc"}]}},
        {"id":"e2","summary":"Offsite","start":{"date":"2026-11-18"},"end":{"date":"2026-11-19"}}]}
        """

    @Test func listsCalendarsWithReaderRoleAndLimitedFields() async throws {
        let recorder = Recorder()
        let connector = makeConnector(recorder: recorder) { _ in Reply(Self.calendars) }
        let calendars = try await connector.calendars(for: "ann@example.com")
        #expect(calendars.map(\.id) == ["ann@example.com"])
        #expect(calendars[0].primary == true)
        let url = try #require(await recorder.requests.first?.url)
        #expect(url.path() == "/calendar/v3/users/me/calendarList")
        #expect(query(url, "minAccessRole") == "reader")
        #expect(await recorder.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer first-token")
    }

    @Test func listsEventsInAWindowAndDecodesThem() async throws {
        let recorder = Recorder()
        let connector = makeConnector(recorder: recorder) { _ in Reply(Self.events) }
        let start = Date(timeIntervalSince1970: 1_794_000_000)
        let events = try await connector.events(
            in: "ann@example.com", from: start, to: start.addingTimeInterval(86400), for: "ann@example.com")
        #expect(events.map(\.id) == ["e1", "e2"])
        #expect(events[0].start.dateTime == ISO8601DateFormatter().date(from: "2026-11-17T10:00:00+05:30"))
        #expect(events[0].attendees?.count == 2)
        #expect(events[0].attendees?[1].`self` == true)
        #expect(events[0].conferenceData?.entryPoints?.first?.uri == "https://meet.google.com/abc")
        #expect(events[1].start.date == "2026-11-18")
        let url = try #require(await recorder.requests.first?.url)
        #expect(url.path() == "/calendar/v3/calendars/ann@example.com/events")
        #expect(query(url, "singleEvents") == "true")
        #expect(query(url, "orderBy") == "startTime")
        #expect(query(url, "timeMin")?.hasSuffix("Z") == true)
        #expect(query(url, "fields")?.contains("attendees(email,displayName,responseStatus,self,organizer)") == true)
    }

    @Test func calendarIDWithHashIsEncodedInThePath() throws {
        let url = try GoogleConnector.eventsURL(calendarID: "x#y@group", from: .now, to: .now, pageToken: nil)
        #expect(url.absoluteString.contains("/calendars/x%23y@group/events"))
    }

    @Test func followsPages() async throws {
        let recorder = Recorder()
        let connector = makeConnector(recorder: recorder) { request in
            query(request.url, "pageToken") == nil
                ? Reply(#"{"items":[{"id":"a","accessRole":"reader"}],"nextPageToken":"p2"}"#)
                : Reply(#"{"items":[{"id":"b","accessRole":"reader"}]}"#)
        }
        #expect(try await connector.calendars(for: "ann@example.com").map(\.id) == ["a", "b"])
    }

    @Test func aBadAnswerIsATypedDecodingError() async {
        let connector = makeConnector(recorder: Recorder()) { _ in Reply(#"{"items":[{"summary":"no id"}]}"#) }
        await #expect(throws: GoogleError.self) { _ = try await connector.calendars(for: "ann@example.com") }
    }

    @Test func aBadDateIsATypedDecodingError() async {
        let bad = #"{"items":[{"id":"e","start":{"dateTime":"yesterday"},"end":{"date":"2026-11-19"}}]}"#
        let connector = makeConnector(recorder: Recorder()) { _ in Reply(bad) }
        await #expect(throws: GoogleError.self) {
            _ = try await connector.events(in: "c", from: .now, to: .now, for: "ann@example.com")
        }
    }

    @Test func a401RefreshesOnceAndRetries() async throws {
        let recorder = Recorder()
        let connector = makeConnector(recorder: recorder) { request in
            request.value(forHTTPHeaderField: "Authorization") == "Bearer refreshed-token"
                ? Reply(Self.calendars) : Reply("expired", status: 401)
        }
        #expect(try await connector.calendars(for: "ann@example.com").count == 1)
        #expect(await recorder.refreshFlags == [false, true])
    }

    @Test func aSecond401IsUnauthorized() async {
        let recorder = Recorder()
        let connector = makeConnector(recorder: recorder) { _ in Reply("expired", status: 401) }
        await #expect(throws: GoogleError.unauthorized(email: "ann@example.com")) {
            _ = try await connector.calendars(for: "ann@example.com")
        }
        #expect(await recorder.refreshFlags == [false, true])
    }

    @Test func otherHTTPErrorsAreTyped() async {
        let connector = makeConnector(recorder: Recorder()) { _ in Reply("boom", status: 500) }
        await #expect(throws: GoogleError.http(status: 500, body: "boom")) {
            _ = try await connector.calendars(for: "ann@example.com")
        }
    }
}
