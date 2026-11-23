import Foundation

/// A Chromium browser on this Mac: the one kind of browser the Workbench extension and its native host can work in.
public struct ChromiumBrowser: Sendable, Hashable, Identifiable {
    public let bundleID: String
    public let name: String
    public let app: URL

    public var id: String { bundleID }

    /// Nil unless `app` is a Chromium browser by its structure.
    public init?(app: URL) {
        guard WebBrowserApp.isChromium(app), let info = WebBrowserApp.info(of: app),
            let bundleID = info["CFBundleIdentifier"] as? String
        else { return nil }
        self.bundleID = bundleID
        self.name =
            info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String
            ?? app.deletingPathExtension().lastPathComponent
        self.app = app
    }
}
