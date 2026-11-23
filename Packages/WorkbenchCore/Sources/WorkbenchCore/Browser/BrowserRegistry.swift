import Foundation

/// A Chromium browser together with the folder where it reads native host manifests.
public struct InstalledBrowser: Sendable, Equatable, Identifiable {
    public let browser: ChromiumBrowser
    /// The browser's own folder in Application Support: the one that holds its `Local State`.
    public let userDataFolder: URL

    public var id: String { browser.bundleID }
    public var hostsFolder: URL { userDataFolder.appending(path: "NativeMessagingHosts") }
}

/// The one list of browsers on this Mac, found by the structure of their app bundles and data folders.
public enum BrowserRegistry {
    /// The Chromium browsers that sit in `applicationFolders` and have a data folder in `applicationSupport`. A browser
    /// that was never opened has no data folder yet and is not listed.
    public static func installed(applicationFolders: [URL], applicationSupport: URL) -> [InstalledBrowser] {
        let folders = userDataFolders(in: applicationSupport)
        return applicationFolders.flatMap(apps(in:)).compactMap { app -> InstalledBrowser? in
            guard let browser = ChromiumBrowser(app: app),
                let folder = ownFolder(of: browser, among: folders, root: applicationSupport)
            else { return nil }
            return InstalledBrowser(browser: browser, userDataFolder: folder)
        }
        .sorted { $0.browser.name < $1.browser.name }
    }

    /// The browsers in the system and user application folders.
    public static func installedHere() -> [InstalledBrowser] {
        installed(
            applicationFolders: [URL(filePath: "/Applications"), URL.homeDirectory.appending(path: "Applications")],
            applicationSupport: URL.applicationSupportDirectory)
    }

    private static func apps(in folder: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasSuffix(".app") }.map { folder.appending(path: $0) }
    }

    /// Folders one or two levels below `root` that hold a `Local State` file: where a Chromium browser keeps its data.
    private static func userDataFolders(in root: URL) -> [URL] {
        let fileManager = FileManager.default
        let children = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let grandchildren = children.flatMap {
            (try? fileManager.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? []
        }
        return (children + grandchildren).filter {
            fileManager.fileExists(atPath: $0.appending(path: "Local State").path)
        }
    }

    /// The data folder whose path ends with the browser's name, ignoring case, spaces and punctuation. A trailing
    /// "User Data" folder counts as the folder around it. An exact match wins over a longer one.
    private static func ownFolder(of browser: ChromiumBrowser, among folders: [URL], root: URL) -> URL? {
        let wanted = squeezed(browser.name)
        let matches = folders.filter { squeezed(namingPath(of: $0, in: root)).hasSuffix(wanted) }
        return matches.min {
            squeezed(namingPath(of: $0, in: root)).count < squeezed(namingPath(of: $1, in: root)).count
        }
    }

    private static func namingPath(of folder: URL, in root: URL) -> String {
        relativePath(
            of: folder.lastPathComponent == "User Data" ? folder.deletingLastPathComponent() : folder, in: root)
    }

    private static func relativePath(of folder: URL, in root: URL) -> String {
        String(folder.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count))
    }

    private static func squeezed(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
