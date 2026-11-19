import Foundation

/// What is on screen at one moment, as read from the accessibility tree.
public struct ScreenSnapshot: Equatable, Sendable {
    public var app: String
    public var bundleID: String
    /// The window element, independent of its title: a title can animate while the window stays the same.
    public var windowID: Int
    /// What the window shows: a browser's URL or a document's file URL. Empty when the app has none.
    public var document: String
    public var title: String
    public var text: String
    /// The focused element is a password field.
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
        /// `page` is a page's visible text from the browser extension; `text` is a window's Accessibility text.
        case window, text, page, idle, active, skipped, file, sleep, wake

        var source: SourceKind { self == .file ? .files : .screen }
    }

    /// Set when read from the store.
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

/// Activity a recorder kept after the policy allowed it. Only the engine in this module can make one.
public struct ActivityBatch: Sendable, Equatable {
    public let activities: [Activity]
    let grant: CaptureGrant

    init?(_ activities: [Activity], grant: CaptureGrant) {
        guard !activities.isEmpty else { return nil }
        self.activities = activities
        self.grant = grant
    }
}
