import AppKit
import Foundation
import SwiftUI
import Testing
import WorkbenchCore

@testable import WorkbenchUI

@MainActor
@Suite struct BrowserSetupTests {
    private struct Rig {
        let setup: BrowserSetup
        let capture: CaptureSettings
        let browser: InstalledBrowser
        let host: URL
        var manifest: URL { browser.hostsFolder.appending(path: NativeHost.fileName) }
        var hasManifest: Bool { FileManager.default.fileExists(atPath: manifest.path) }
    }

    private func rig(
        connected: Set<String> = [], extensionFolder: URL? = nil
    ) throws -> Rig {
        let root = scratchFolder()
        let browser = try BrowserFixtureUI.installed("Alpha", bundleID: "x.alpha", in: root)
        let capture = try captureSettings()
        let host = root.appending(path: "Workbench.app/Contents/Helpers/workbench-pages")
        let setup = BrowserSetup(
            capture: capture, registry: { [browser] }, connectedBrowsers: { connected }, host: host,
            extensionFolder: try extensionFolder ?? BrowserFixtureUI.extensionFolder(in: root))
        setup.recheck()
        return Rig(setup: setup, capture: capture, browser: browser, host: host)
    }

    @Test func turningABrowserOnWritesItsManifestAndTurningItOffRemovesIt() throws {
        let rig = try rig()
        #expect(!rig.hasManifest && rig.setup.facts.map(\.isEnabled) == [false])
        rig.setup.turn(rig.browser, on: true)
        #expect(rig.hasManifest && rig.setup.facts.map(\.isEnabled) == [true] && rig.setup.problem == nil)
        let written = try JSONSerialization.jsonObject(with: Data(contentsOf: rig.manifest)) as? [String: Any]
        #expect(written?["path"] as? String == rig.host.path, "the manifest points into the app bundle")
        rig.setup.turn(rig.browser, on: false)
        #expect(!rig.hasManifest && rig.setup.facts.map(\.isEnabled) == [false])
        #expect(rig.capture.enabledBrowsers.isEmpty)
    }

    @Test func theLaunchRefreshWritesOnlyForAnEnabledBrowserAndRemovesNothing() throws {
        let rig = try rig()
        rig.setup.refreshEnabledBrowsers()
        #expect(!rig.hasManifest, "no yes, no manifest")
        try FileManager.default.createDirectory(at: rig.browser.hostsFolder, withIntermediateDirectories: true)
        try Data("from an older setup".utf8).write(to: rig.manifest)
        rig.setup.refreshEnabledBrowsers()
        #expect(
            try String(contentsOf: rig.manifest, encoding: .utf8) == "from an older setup", "launch removes nothing")
        rig.capture.set(rig.browser.browser, on: true)
        rig.setup.refreshEnabledBrowsers()
        #expect(try String(contentsOf: rig.manifest, encoding: .utf8).contains(rig.host.path), "a yes refreshes it")
    }

    @Test func aBrowserIsConnectedOnlyWhenTheExtensionTalkedThroughTheHost() throws {
        let waiting = try rig()
        waiting.setup.turn(waiting.browser, on: true)
        #expect(waiting.setup.facts.map(\.isConnected) == [false])
        let talking = try rig(connected: ["x.alpha"])
        #expect(talking.setup.facts.map(\.isConnected) == [true])
    }

    @Test func aMissingExtensionFolderIsShownAndWritesNothing() throws {
        let rig = try rig(extensionFolder: scratchFolder())
        rig.setup.turn(rig.browser, on: true)
        #expect(!rig.hasManifest && rig.setup.problem?.hasPrefix("Alpha:") == true)
    }

    @Test func theConnectRowsAreDrawnForEveryState() throws {
        _ = NSApplication.shared
        guard case .ready(let session) = AppLaunch.start(storeFolder: scratchFolder()) else {
            throw CocoaError(.fileReadUnknown)
        }
        let root = scratchFolder()
        let browsers = ["Alpha", "Beta", "Gamma"].map { name in
            (try? BrowserFixtureUI.installed(name, bundleID: "x.\(name.lowercased())", in: root))!
        }
        let setup = BrowserSetup(
            capture: session.capture, registry: { browsers }, connectedBrowsers: { ["x.gamma"] },
            host: root.appending(path: "host"), extensionFolder: try BrowserFixtureUI.extensionFolder(in: root))
        setup.recheck()
        setup.turn(browsers[1], on: true)
        setup.turn(browsers[2], on: true)
        let states = ConnectFacts(readerFound: true, browsers: setup.facts, needsBrowser: true, sourceRows: [])
        try renderPNG(
            ConnectList(facts: states, needs: TeamTemplate.fund.sourceNeeds).environment(setup).environment(MacAccess())
                .environment(session),
            named: "connect-browser-states")
        let none = ConnectFacts(readerFound: true, needsBrowser: true, sourceRows: [])
        try renderPNG(
            ConnectList(facts: none, needs: TeamTemplate.fund.sourceNeeds).environment(setup).environment(MacAccess())
                .environment(session),
            named: "connect-browser-not-installed")
    }
}

private enum BrowserFixtureUI {
    static func installed(_ name: String, bundleID: String, in root: URL) throws -> InstalledBrowser {
        let apps = root.appending(path: "Applications")
        let app = apps.appending(path: "\(name).app")
        let contents = app.appending(path: "Contents")
        try FileManager.default.createDirectory(
            at: contents.appending(path: "Frameworks/\(name) Framework.framework"), withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleID, "CFBundleDisplayName": name,
            "CFBundleURLTypes": [["CFBundleURLSchemes": ["https"]]],
        ]
        try (plist as NSDictionary).write(to: contents.appending(path: "Info.plist"))
        let data = root.appending(path: "Support/\(name)")
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: data.appending(path: "Local State"))
        let found = BrowserRegistry.installed(
            applicationFolders: [apps], applicationSupport: root.appending(path: "Support"))
        return try #require(found.first { $0.id == bundleID })
    }

    /// A folder with the manifest of the real extension: only its public key matters.
    static func extensionFolder(in root: URL) throws -> URL {
        let folder = root.appending(path: "Extension")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let real = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Extension/manifest.json")
        try FileManager.default.copyItem(at: real, to: folder.appending(path: "manifest.json"))
        return folder
    }
}
