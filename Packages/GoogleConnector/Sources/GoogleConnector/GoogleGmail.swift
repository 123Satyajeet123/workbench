import Foundation

public struct WorkbenchLabel: Sendable, Equatable {
    public let id: String

    public static let name = "Workbench"
}

public enum WorkbenchLabelLookup: Sendable, Equatable {
    case found(WorkbenchLabel)
    case missing
}

public struct GmailMessage: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let threadId: String?
    public let labelIds: [String]?
    public let snippet: String?
    public let internalDate: String?
    public let payload: GmailPart?
}

public struct GmailPart: Decodable, Sendable, Equatable {
    public let mimeType: String?
    public let filename: String?
    public let headers: [GmailHeader]?
    public let body: GmailBody?
    public let parts: [GmailPart]?
}

public struct GmailHeader: Decodable, Sendable, Equatable {
    public let name: String
    public let value: String
}

public struct GmailBody: Decodable, Sendable, Equatable {
    public let size: Int?
    public let data: String?
    public let attachmentId: String?
}

private struct LabelsResponse: Decodable {
    struct Label: Decodable {
        let id: String
        let name: String
    }
    let labels: [Label]?
}

private struct MessageIDsResponse: PagedResponse {
    struct Reference: Decodable, Sendable {
        let id: String
    }
    let messages: [Reference]?
    let nextPageToken: String?
    var pageItems: [String] { (messages ?? []).map(\.id) }
}

extension GoogleConnector {
    static func labelsURL() throws -> URL {
        try GoogleURL.make(GoogleEndpoint.gmailBase, segments: ["users", "me", "labels"], query: [])
    }

    static func messageIDsURL(in label: WorkbenchLabel, pageToken: String?) throws -> URL {
        try GoogleURL.make(
            GoogleEndpoint.gmailBase, segments: ["users", "me", "messages"],
            query: [
                URLQueryItem(name: "labelIds", value: label.id),
                URLQueryItem(name: "maxResults", value: "500"),
                URLQueryItem(name: "fields", value: "nextPageToken,messages/id"),
            ] + pageTokenQuery(pageToken))
    }

    static func messageURL(id: String, format: String) throws -> URL {
        guard !id.isEmpty, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            throw GoogleError.invalidMessageID(id)
        }
        let fields = format == "minimal" ? [URLQueryItem(name: "fields", value: "id,labelIds")] : []
        return try GoogleURL.make(
            GoogleEndpoint.gmailBase, segments: ["users", "me", "messages", id],
            query: [URLQueryItem(name: "format", value: format)] + fields)
    }

    public func workbenchLabel(for email: String) async throws -> WorkbenchLabelLookup {
        try requireGmail(for: email)
        let response = try await getDecoded(try Self.labelsURL(), for: email, as: LabelsResponse.self)
        guard let label = response.labels?.first(where: { $0.name == WorkbenchLabel.name }) else { return .missing }
        return .found(WorkbenchLabel(id: label.id))
    }

    public func messageIDs(in label: WorkbenchLabel, for email: String) async throws -> [String] {
        try requireGmail(for: email)
        return try await allPages(MessageIDsResponse.self, for: email) {
            try Self.messageIDsURL(in: label, pageToken: $0)
        }
    }

    public func message(id: String, in label: WorkbenchLabel, for email: String) async throws -> GmailMessage {
        try requireGmail(for: email)
        let labels = try await getDecoded(
            try Self.messageURL(id: id, format: "minimal"), for: email, as: GmailMessage.self)
        try Self.requireLabel(label, in: labels)
        let message = try await getDecoded(
            try Self.messageURL(id: id, format: "full"), for: email, as: GmailMessage.self)
        try Self.requireLabel(label, in: message)
        return message
    }

    private static func requireLabel(_ label: WorkbenchLabel, in message: GmailMessage) throws {
        guard message.labelIds?.contains(label.id) == true else {
            throw GoogleError.messageOutsideWorkbenchLabel(id: message.id)
        }
    }
}
