import Foundation

public struct CallSource: Equatable, Sendable {
    public var service: String
    public var title: String
    public var isCall: Bool

    public init(service: String, title: String = "", isCall: Bool = true) {
        self.service = service
        self.title = title
        self.isCall = isCall
    }

    public var label: String { title.isEmpty ? service : "\(service) · \(title)" }

    static let inPerson = CallSource(service: "In person")

    /// The service comes from the address or the bundle id. The title is the title of the calendar event whose join
    /// link is the address; else the window's own title, as it is, unless it only repeats the name of the app or the
    /// service.
    public static func identify(
        app: String, bundleID: String, windowTitle: String, address: String, meetings: [Meeting] = []
    ) -> CallSource {
        if bundleID == "in-person" { return inPerson }
        let services = SourceDescriptor.callTranscript.callServices
        let known = services.service(atAddress: address) ?? services.apps[bundleID]
        let service = known ?? app
        let event = meetings.first { $0.joinURL.map { MeetingLink.joins($0, address: address) } ?? false }
        let title = event?.title ?? windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let repeatsName = [app, service].contains { $0.caseInsensitiveCompare(title) == .orderedSame }
        return CallSource(service: service, title: repeatsName ? "" : title, isCall: known != nil)
    }
}
