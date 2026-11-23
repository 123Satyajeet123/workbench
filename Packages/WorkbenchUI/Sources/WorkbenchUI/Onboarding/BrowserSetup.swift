import AppKit
import Foundation
import Observation
import WorkbenchCore

/// The Chromium browsers on this Mac and where each one stands: not enabled, waiting for the extension, or connected.
/// Enabling a browser writes its native host manifest; disabling it removes the manifest.
@Observable
final class BrowserSetup {
    private let capture: CaptureSettings
    private let registry: () -> [InstalledBrowser]
    private let connectedBrowsers: () -> Set<String>
    private let host: URL
    private let extensionFolder: URL
    private(set) var installed: [InstalledBrowser] = []
    private(set) var connected: Set<String> = []
    private(set) var problem: String?

    init(
        capture: CaptureSettings, registry: @escaping () -> [InstalledBrowser] = BrowserRegistry.installedHere,
        connectedBrowsers: @escaping () -> Set<String>, host: URL = BrowserSetup.bundledHost,
        extensionFolder: URL = BrowserSetup.bundledExtension
    ) {
        self.capture = capture
        self.registry = registry
        self.connectedBrowsers = connectedBrowsers
        self.host = host
        self.extensionFolder = extensionFolder
    }

    static var bundledHost: URL { Bundle.main.bundleURL.appending(path: "Contents/Helpers/workbench-pages") }
    static var bundledExtension: URL { Bundle.main.bundleURL.appending(path: "Contents/Resources/Extension") }

    var facts: [BrowserFact] {
        installed.map {
            BrowserFact(
                id: $0.id, name: $0.browser.name, isEnabled: capture.enabledBrowsers.contains($0.id),
                isConnected: connected.contains($0.id))
        }
    }

    /// Reads the browsers and the connections again. It changes nothing on disk.
    func recheck() {
        installed = registry()
        connected = connectedBrowsers()
    }

    /// At launch: every enabled browser gets a manifest that points at the host in this app, wherever the app is now.
    func refreshEnabledBrowsers() {
        recheck()
        sync(installed.filter { capture.enabledBrowsers.contains($0.id) })
    }

    func turn(_ browser: InstalledBrowser, on: Bool) {
        capture.set(browser.browser, on: on)
        sync([browser])
    }

    /// Load unpacked needs both: the browser's extensions page and the folder to pick.
    func startLoading(in browser: InstalledBrowser) {
        NSWorkspace.shared.open(
            [Self.extensionsPage], withApplicationAt: browser.browser.app,
            configuration: NSWorkspace.OpenConfiguration())
        NSWorkspace.shared.activateFileViewerSelecting([extensionFolder])
    }

    private static let extensionsPage = URL(string: "chrome://extensions")!

    private func sync(_ browsers: [InstalledBrowser]) {
        let failures = NativeHost.sync(
            browsers, enabled: capture.enabledBrowsers, executable: host,
            extensionID: NativeHost.extensionID(inExtensionFolder: extensionFolder))
        problem = failures.first.map { failure in
            "\(browsers.first { $0.id == failure.bundleID }?.browser.name ?? "A browser"): \(failure.reason)"
        }
    }
}
