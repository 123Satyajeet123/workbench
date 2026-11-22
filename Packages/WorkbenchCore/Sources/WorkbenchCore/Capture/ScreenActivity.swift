import Foundation

public struct ScreenSnapshot: Equatable, Sendable {
    public var app: String
    public var bundleID: String
    public var windowID: Int
    public var document: String
    public var title: String
    public var text: String
    public var secureFocus: Bool

    public init(
        app: String, bundleID: String, windowID: Int, document: String = "", title: String, text: String,
        secureFocus: Bool = false
    ) {
        self.app = app
        self.bundleID = bundleID
        self.windowID = windowID
        self.document = document
        self.title = title
        self.text = text
        self.secureFocus = secureFocus
    }

    var place: String { "\(bundleID)#\(windowID)#\(document)" }
}

public struct Activity: Equatable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case window, text, page, idle, active, skipped, file, sleep, wake

        var source: SourceKind { self == .file ? .files : .screen }
    }

    public var id: Int64?
    public var at: Date
    public var kind: Kind
    public var app: String
    public var bundleID: String
    public var title: String
    public var document: String?
    public var text: String?

    public init(
        id: Int64? = nil, at: Date, kind: Kind, app: String = "", bundleID: String = "", title: String = "",
        document: String? = nil, text: String? = nil
    ) {
        self.id = id
        self.at = at
        self.kind = kind
        self.app = app
        self.bundleID = bundleID
        self.title = title
        self.document = document
        self.text = text
    }
}

public struct ActivityBatch: Sendable, Equatable {
    public let activities: [Activity]
    let grant: CaptureGrant

    init?(_ activities: [Activity], grant: CaptureGrant) {
        guard !activities.isEmpty else { return nil }
        self.activities = activities
        self.grant = grant
    }
}
