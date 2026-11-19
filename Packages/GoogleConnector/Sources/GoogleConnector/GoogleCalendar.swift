import Foundation

public struct GoogleCalendar: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let summary: String?
    public let primary: Bool?
    public let accessRole: String
    public let timeZone: String?
}

public struct GoogleEvent: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let status: String?
    public let summary: String?
    public let description: String?
    public let start: GoogleEventTime
    public let end: GoogleEventTime
    public let attendees: [Attendee]?
    public let organizer: Organizer?
    public let hangoutLink: String?
    public let conferenceData: ConferenceData?
    public let eventType: String?

    public struct Attendee: Decodable, Sendable, Equatable {
        public let email: String?
        public let displayName: String?
        public let responseStatus: String?
        public let `self`: Bool?
        public let organizer: Bool?
    }

    public struct Organizer: Decodable, Sendable, Equatable {
        public let email: String?
        public let displayName: String?
        public let `self`: Bool?
    }

    public struct ConferenceData: Decodable, Sendable, Equatable {
        public let entryPoints: [EntryPoint]?
    }

    public struct EntryPoint: Decodable, Sendable, Equatable {
        public let entryPointType: String?
        public let uri: String?
        public let label: String?
    }
}

public struct GoogleEventTime: Decodable, Sendable, Equatable {
    public let dateTime: Date?
    public let date: String?
    public let timeZone: String?

    private enum CodingKeys: String, CodingKey {
        case dateTime, date, timeZone
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decodeIfPresent(String.self, forKey: .date)
        timeZone = try container.decodeIfPresent(String.self, forKey: .timeZone)
        dateTime = try container.decodeIfPresent(String.self, forKey: .dateTime).map {
            try Date($0, strategy: .iso8601)
        }
    }
}

private struct CalendarListResponse: PagedResponse {
    let items: [GoogleCalendar]?
    let nextPageToken: String?
    var pageItems: [GoogleCalendar] { items ?? [] }
}

private struct EventsResponse: PagedResponse {
    let items: [GoogleEvent]?
    let nextPageToken: String?
    var pageItems: [GoogleEvent] { items ?? [] }
}

extension GoogleConnector {
    static let eventFields =
        "nextPageToken,items(id,status,summary,start,end,attendees(email,displayName,responseStatus,self,organizer),"
        + "organizer,hangoutLink,conferenceData/entryPoints,eventType,description)"

    static func calendarListURL(pageToken: String?) throws -> URL {
        try GoogleURL.make(
            GoogleEndpoint.calendarBase, segments: ["users", "me", "calendarList"],
            query: [
                URLQueryItem(name: "minAccessRole", value: "reader"),
                URLQueryItem(name: "fields", value: "nextPageToken,items(id,summary,primary,accessRole,timeZone)"),
            ] + pageTokenQuery(pageToken))
    }

    static func eventsURL(calendarID: String, from start: Date, to end: Date, pageToken: String?) throws -> URL {
        try GoogleURL.make(
            GoogleEndpoint.calendarBase, segments: ["calendars", calendarID, "events"],
            query: [
                URLQueryItem(name: "timeMin", value: GoogleURL.utc(start)),
                URLQueryItem(name: "timeMax", value: GoogleURL.utc(end)),
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "orderBy", value: "startTime"),
                URLQueryItem(name: "maxResults", value: "250"),
                URLQueryItem(name: "fields", value: eventFields),
            ] + pageTokenQuery(pageToken))
    }

    public func calendars(for email: String) async throws -> [GoogleCalendar] {
        try await allPages(CalendarListResponse.self, for: email) { try Self.calendarListURL(pageToken: $0) }
    }

    public func events(
        in calendarID: String, from start: Date, to end: Date, for email: String
    ) async throws -> [GoogleEvent] {
        try await allPages(EventsResponse.self, for: email) {
            try Self.eventsURL(calendarID: calendarID, from: start, to: end, pageToken: $0)
        }
    }

    static func pageTokenQuery(_ pageToken: String?) -> [URLQueryItem] {
        pageToken.map { [URLQueryItem(name: "pageToken", value: $0)] } ?? []
    }
}
