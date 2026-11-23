import Foundation

/// Whether Workbench works with one browser, as a value a health view can show. `problem` is nil when it works.
public struct BrowserHealth: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let problem: String?

    public var isHealthy: Bool { problem == nil }
}

extension CapturePolicy {
    /// A browser that is not known fails closed, and so does one the person did not enable.
    public func health(ofBrowser browser: ChromiumBrowser?) -> BrowserHealth {
        guard let browser else {
            return BrowserHealth(id: "", name: "Unknown browser", problem: "Workbench does not know this browser.")
        }
        return BrowserHealth(
            id: browser.bundleID, name: browser.name,
            problem: isEnabled(browser: browser.bundleID) ? nil : "\(browser.name) is not enabled for Workbench.")
    }
}
