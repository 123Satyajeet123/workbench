import Foundation
import Testing

@testable import WorkbenchCore

@Suite struct NativeHostTests {
    private let executable = URL(filePath: "/Apps/Workbench.app/Contents/Helpers/workbench-pages")
    private let extensionID = "ambibkofkkdemncaffilfcmlofcncpcc"

    private func manifestFile(of browser: InstalledBrowser) -> URL {
        browser.hostsFolder.appending(path: NativeHost.fileName)
    }

    @Test func theExtensionIdIsTheOneChromiumGivesTheKey() throws {
        let folder = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Extension")
        #expect(NativeHost.extensionID(inExtensionFolder: folder) == extensionID, "measured in a real browser")
        #expect(NativeHost.extensionID(publicKey: "not base64 !!") == nil)
        #expect(NativeHost.extensionID(inExtensionFolder: temporaryDirectory()) == nil, "no manifest")
    }

    @Test func anEnabledBrowserGetsTheManifestAndADisabledOneLosesIt() throws {
        let root = temporaryDirectory()
        let browser = try BrowserFixture.installed("Alpha", bundleID: "x.alpha", in: root, dataPath: "Alpha")
        let on = NativeHost.sync([browser], enabled: [browser.id], executable: executable, extensionID: extensionID)
        #expect(on.isEmpty)
        let written =
            try JSONSerialization.jsonObject(with: Data(contentsOf: manifestFile(of: browser))) as? [String: Any]
        #expect(written?["name"] as? String == "com.hizen.workbench.pages")
        #expect(written?["path"] as? String == executable.path, "the host inside the bundle")
        #expect(written?["allowed_origins"] as? [String] == ["chrome-extension://\(extensionID)/"])
        #expect(written?["type"] as? String == "stdio")

        let off = NativeHost.sync([browser], enabled: [], executable: executable, extensionID: extensionID)
        #expect(off.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: manifestFile(of: browser).path), "disabling removes it")
        #expect(NativeHost.sync([browser], enabled: [], executable: executable, extensionID: extensionID).isEmpty)
    }

    @Test func eachBrowserFollowsItsOwnConsentAndAMovedAppIsRewritten() throws {
        let root = temporaryDirectory()
        let alpha = try BrowserFixture.installed("Alpha", bundleID: "x.alpha", in: root, dataPath: "Alpha")
        let beta = try BrowserFixture.installed("Beta", bundleID: "x.beta", in: root, dataPath: "Beta")
        _ = NativeHost.sync([alpha, beta], enabled: ["x.alpha"], executable: executable, extensionID: extensionID)
        #expect(FileManager.default.fileExists(atPath: manifestFile(of: alpha).path))
        #expect(!FileManager.default.fileExists(atPath: manifestFile(of: beta).path), "not enabled gets nothing")

        let moved = URL(filePath: "/Other/Workbench.app/Contents/Helpers/workbench-pages")
        _ = NativeHost.sync([alpha, beta], enabled: ["x.alpha"], executable: moved, extensionID: extensionID)
        let text = try String(contentsOf: manifestFile(of: alpha), encoding: .utf8)
        #expect(text.contains("/Other/Workbench.app") && !text.contains("/Apps/Workbench.app"))
    }

    @Test func anEnabledBrowserWithoutAnExtensionIdIsReportedAndADisabledOneIsStillCleaned() throws {
        let root = temporaryDirectory()
        let browser = try BrowserFixture.installed("Alpha", bundleID: "x.alpha", in: root, dataPath: "Alpha")
        _ = NativeHost.sync([browser], enabled: [browser.id], executable: executable, extensionID: extensionID)
        let missing = NativeHost.sync([browser], enabled: [browser.id], executable: executable, extensionID: nil)
        #expect(missing.map(\.bundleID) == ["x.alpha"], "no id, no manifest to write")
        #expect(NativeHost.sync([browser], enabled: [], executable: executable, extensionID: nil).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: manifestFile(of: browser).path))
    }

    @Test func aFolderThatCannotBeWrittenIsReportedWithTheBrowser() throws {
        let root = temporaryDirectory()
        let browser = try BrowserFixture.installed("Alpha", bundleID: "x.alpha", in: root, dataPath: "Alpha")
        try Data("a file where the folder belongs".utf8).write(to: browser.hostsFolder)
        let failures = NativeHost.sync(
            [browser], enabled: [browser.id], executable: executable, extensionID: extensionID)
        #expect(failures.map(\.bundleID) == ["x.alpha"] && failures.first?.reason.isEmpty == false)
    }
}

@Suite struct BrowserHealthTests {
    private func browser() throws -> ChromiumBrowser {
        let app = try BrowserFixture.app(in: temporaryDirectory(), named: "Alpha", bundleID: "x.alpha")
        return try #require(ChromiumBrowser(app: app))
    }

    @Test func aBrowserIsHealthyOnlyWhenThePersonEnabledIt() throws {
        let alpha = try browser()
        let off = CapturePolicy().health(ofBrowser: alpha)
        #expect(!off.isHealthy && off.problem == "Alpha is not enabled for Workbench.")
        let on = CapturePolicy(browsers: ["x.alpha": "Alpha"]).health(ofBrowser: alpha)
        #expect(on.isHealthy && on.id == "x.alpha" && on.name == "Alpha")
    }

    @Test func anUnknownBrowserFailsClosedWithAReason() {
        let health = CapturePolicy(browsers: ["x.alpha": "Alpha"]).health(ofBrowser: nil)
        #expect(!health.isHealthy && health.problem == "Workbench does not know this browser.")
    }

    @Test func aPolicyStoredBeforeBrowserConsentStillReadsAndEnablesNoBrowser() throws {
        let old = try JSONEncoder().encode(CapturePolicy(switches: [.screen: true]))
        var object = try #require(try JSONSerialization.jsonObject(with: old) as? [String: Any])
        object["browsers"] = nil
        let policy = try JSONDecoder().decode(CapturePolicy.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(policy.isEnabled(.screen) && policy.browsers.isEmpty)
        let roundTrip = try JSONDecoder().decode(
            CapturePolicy.self, from: JSONEncoder().encode(CapturePolicy(browsers: ["x.alpha": "Alpha"])))
        #expect(roundTrip.isEnabled(browser: "x.alpha") && !roundTrip.isEnabled(browser: "x.beta"))
    }
}
