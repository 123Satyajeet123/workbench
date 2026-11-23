import Darwin
import Foundation
import Testing

@testable import WorkbenchCore

/// The app names the browser from the process tree, not from the message.
@Suite struct PeerBrowserTests {
    @Test func aPathNamesAnAppOnlyAtTheAppExecutableSlot() {
        let browser = "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"
        #expect(PeerBrowser.appBundle(ofExecutable: browser)?.path == "/Applications/Brave Browser.app")
        let helper =
            "/Applications/Brave Browser.app/Contents/Frameworks/F.framework/Helpers/Brave Helper.app/Contents/MacOS/Brave Helper"
        #expect(
            PeerBrowser.appBundle(ofExecutable: helper)?.lastPathComponent == "Brave Helper.app",
            "a helper is its own app, not the browser around it")
        for outside in [
            "/usr/bin/xctest", "/Applications/Brave Browser.app/Contents/Resources/tool",
            "/Applications/Brave Browser.app/Contents/Frameworks/tool", "/sbin/launchd", "",
            "/tmp/NotAnApp/Contents/MacOS/x",
        ] {
            #expect(PeerBrowser.appBundle(ofExecutable: outside) == nil, "\(outside)")
        }
    }

    @Test func theBundleIdComesFromAChromiumBrowserAppAndFromNoOtherApp() throws {
        let root = temporaryDirectory()
        func executable(of app: URL) -> String { app.appending(path: "Contents/MacOS/x").path }
        let browser = try BrowserFixture.app(in: root, named: "Alpha", bundleID: "x.alpha")
        #expect(PeerBrowser.bundleID(ofExecutable: executable(of: browser)) == "x.alpha", "the control")
        let notChromium = try BrowserFixture.app(in: root, named: "Fox", bundleID: "x.fox", chromiumFramework: false)
        let notABrowser = try BrowserFixture.app(in: root, named: "Chat", bundleID: "x.chat", schemes: ["chat"])
        #expect(PeerBrowser.bundleID(ofExecutable: executable(of: notChromium)) == nil)
        #expect(PeerBrowser.bundleID(ofExecutable: executable(of: notABrowser)) == nil)
        #expect(PeerBrowser.bundleID(ofExecutable: "/usr/bin/xctest") == nil)
        let bare = root.appending(path: "Bare.app/Contents/MacOS")
        try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
        #expect(PeerBrowser.bundleID(ofExecutable: bare.appending(path: "x").path) == nil, "an app with no Info.plist")
    }

    @Test func theProcessAtTheOtherEndOfASocketIsFound() throws {
        var pair: [Int32] = [0, 0]
        try #require(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0)
        defer { for end in pair { close(end) } }
        #expect(PeerBrowser.peerProcess(of: pair[0]) == getpid(), "both ends are this process")
        var pipes: [Int32] = [0, 0]
        try #require(pipe(&pipes) == 0)
        defer { for end in pipes { close(end) } }
        #expect(PeerBrowser.peerProcess(of: pipes[0]) == nil, "a pipe has no peer process")
        #expect(PeerBrowser.peerProcess(of: -1) == nil)
    }

    @Test func aProcessGivesItsParentAndItsExecutable() throws {
        #expect(PeerBrowser.parentProcess(of: getpid()) == getppid())
        #expect(PeerBrowser.parentProcess(of: 99_999_999) == nil)
        let path = try #require(PeerBrowser.executablePath(of: getpid()))
        #expect(path == (try #require(PeerBrowser.executablePath(of: getpid()))) && path.hasPrefix("/"))
        #expect(PeerBrowser.executablePath(of: 99_999_999) == nil)
    }
}
