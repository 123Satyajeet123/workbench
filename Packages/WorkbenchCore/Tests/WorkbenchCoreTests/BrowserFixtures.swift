import Foundation
import Testing

@testable import WorkbenchCore

/// App bundles and data folders made in a temporary folder, shaped like the real ones.
enum BrowserFixture {
    @discardableResult
    static func app(
        in folder: URL, named name: String, bundleID: String, schemes: [String] = ["http", "https"],
        chromiumFramework: Bool = true
    ) throws -> URL {
        let app = folder.appending(path: "\(name).app")
        let contents = app.appending(path: "Contents")
        try FileManager.default.createDirectory(
            at: contents.appending(path: "MacOS"), withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleID, "CFBundleDisplayName": name,
            "CFBundleURLTypes": [["CFBundleURLSchemes": schemes]],
        ]
        try (plist as NSDictionary).write(to: contents.appending(path: "Info.plist"))
        if chromiumFramework {
            try FileManager.default.createDirectory(
                at: contents.appending(path: "Frameworks/\(name) Framework.framework"),
                withIntermediateDirectories: true)
        }
        return app
    }

    @discardableResult
    static func dataFolder(in support: URL, _ path: String) throws -> URL {
        let folder = support.appending(path: path)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: folder.appending(path: "Local State"))
        return folder
    }

    static func installed(_ name: String, bundleID: String, in root: URL, dataPath: String) throws -> InstalledBrowser {
        let app = try app(in: root.appending(path: "Applications"), named: name, bundleID: bundleID)
        let data = try dataFolder(in: root.appending(path: "Support"), dataPath)
        return InstalledBrowser(browser: try #require(ChromiumBrowser(app: app)), userDataFolder: data)
    }
}
