import AppKit

/// Installed apps by name and bundle ID, from the standard app folders and Launch Services.
enum InstalledApps {
    static var folders: [URL] {
        [
            URL(filePath: "/Applications"), URL(filePath: "/System/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications"),
        ]
    }

    static func bundleID(named name: String) -> String? {
        let wanted = name.lowercased().replacingOccurrences(of: ".app", with: "")
        guard !wanted.isEmpty else { return nil }
        for folder in folders {
            let apps = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            if let app = apps.first(where: { $0.deletingPathExtension().lastPathComponent.lowercased() == wanted }) {
                return Bundle(url: app)?.bundleIdentifier
            }
        }
        return nil
    }

    static func name(of bundleID: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map {
            $0.deletingPathExtension().lastPathComponent
        }
    }
}
