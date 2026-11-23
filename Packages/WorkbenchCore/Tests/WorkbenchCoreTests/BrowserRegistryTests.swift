import Foundation
import Testing

@testable import WorkbenchCore

/// The registry finds browsers by the structure of an app bundle, never by a name.
@Suite struct BrowserRegistryTests {
    private func registry(_ root: URL) -> [InstalledBrowser] {
        BrowserRegistry.installed(
            applicationFolders: [root.appending(path: "Applications")],
            applicationSupport: root.appending(path: "Support"))
    }

    @Test func aChromiumBrowserIsFoundWithItsOwnDataFolderAndANonChromiumAppIsNot() throws {
        let root = temporaryDirectory()
        let apps = root.appending(path: "Applications")
        try BrowserFixture.app(in: apps, named: "Fox Browser", bundleID: "x.fox", chromiumFramework: false)
        try BrowserFixture.app(in: apps, named: "Chat App", bundleID: "x.chat", schemes: ["chat"])
        try BrowserFixture.app(in: apps, named: "Tool", bundleID: "x.tool", schemes: [])
        try BrowserFixture.app(in: apps, named: "Odd Browser", bundleID: "x.odd")
        try BrowserFixture.app(in: apps, named: "Alpha", bundleID: "x.alpha")
        try BrowserFixture.app(in: apps, named: "Beta Browser", bundleID: "x.beta")
        try BrowserFixture.dataFolder(in: root.appending(path: "Support"), "Vendor/Alpha")
        try BrowserFixture.dataFolder(in: root.appending(path: "Support"), "Beta Browser")
        try BrowserFixture.dataFolder(in: root.appending(path: "Support"), "Chat App")
        try BrowserFixture.dataFolder(in: root.appending(path: "Support"), "Fox Browser")

        let found = registry(root)
        #expect(found.map(\.id) == ["x.alpha", "x.beta"], "the control: two Chromium browsers with a data folder")
        #expect(found.first?.userDataFolder.path.hasSuffix("Support/Vendor/Alpha") == true)
        #expect(found.first?.hostsFolder.lastPathComponent == "NativeMessagingHosts")
    }

    @Test func aBrowserNeverOpenedHasNoDataFolderAndIsNotListed() throws {
        let root = temporaryDirectory()
        try BrowserFixture.app(in: root.appending(path: "Applications"), named: "New Browser", bundleID: "x.new")
        try FileManager.default.createDirectory(at: root.appending(path: "Support"), withIntermediateDirectories: true)
        #expect(registry(root).isEmpty)
    }

    @Test func aLongerNameDoesNotTakeAShorterBrowsersFolder() throws {
        let root = temporaryDirectory()
        try BrowserFixture.app(in: root.appending(path: "Applications"), named: "Vendor Chrome", bundleID: "x.chrome")
        try BrowserFixture.dataFolder(in: root.appending(path: "Support"), "Vendor/Chrome Canary")
        #expect(registry(root).isEmpty, "Chrome Canary's folder is not the folder of Vendor Chrome")
        try BrowserFixture.dataFolder(in: root.appending(path: "Support"), "Vendor/Chrome")
        #expect(registry(root).first?.userDataFolder.lastPathComponent == "Chrome")
    }

    @Test func noBrowserNameOrBundleIdIsWrittenInTheShippedCode() throws {
        let repository = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let folders = ["Packages", "Workbench"].map { repository.appending(path: $0) }
        let files = folders.flatMap { folder in
            (FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
                .filter { $0.pathExtension == "swift" && !$0.path.contains("/Tests/") && !$0.path.contains("/.build/") }
        }
        #expect(files.count > 100, "the scan found the sources")
        let names = [
            "com.brave", "com.google.Chrome", "com.apple.Safari", "company.thebrowser", "com.microsoft.edge",
            "org.mozilla", "Brave Browser", "Google Chrome",
        ]
        for file in files {
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            for name in names { #expect(!text.contains(name), "\(name) in \(file.lastPathComponent)") }
        }
    }
}
