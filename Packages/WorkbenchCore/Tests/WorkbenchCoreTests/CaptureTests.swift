import Foundation
import Testing

@testable import WorkbenchCore

private let screenOn = CapturePolicy(switches: [.screen: true, .screenText: true])
private let filesOn = CapturePolicy(switches: [.files: true])
private let terminal = ScreenSnapshot(
    app: "Terminal", bundleID: "com.apple.Terminal", windowID: 1, title: "claude", text: "hello")
private let sourceFile = "/Users/me/Projects/app/Sources/main.swift"

private func kinds(_ batch: ActivityBatch?) -> [Activity.Kind] { batch?.activities.map(\.kind) ?? [] }

private func snapshot(_ change: (inout ScreenSnapshot) -> Void) -> ScreenSnapshot {
    var value = terminal
    change(&value)
    return value
}

struct ScreenCaptureTests {

    @Test func aSiteTheFounderDeniedIsHiddenWithItsSubdomainsAndOthersAreKept() {
        var recorder = CaptureEngine()
        var policy = screenOn
        policy.denyList = [.screen: ["linkedin.com"]]
        let denied = snapshot { $0.document = "www.linkedin.com/feed" }
        #expect(kinds(recorder.observe(denied, idleSeconds: 0, policy: policy, at: t0)) == [.skipped])
        let other = snapshot { $0.document = "example.com" }
        #expect(kinds(recorder.observe(other, idleSeconds: 0, policy: policy, at: t0)) == [.window, .text])
    }

}

extension CaptureVerdict {
    var isHidden: Bool { if case .hide = self { true } else { false } }
}

private func hidden(_ screen: ScreenSnapshot, policy: CapturePolicy = screenOn) -> Bool {
    policy.verdict(for: screen, at: t0).isHidden
}

struct CaptureVerdictTests {

    @Test func screenTextIsKeptOnlyWithItsOwnConsent() {
        var engine = CaptureEngine()
        let windowOnly = CapturePolicy(switches: [.screen: true])
        #expect(!engine.wantsText(for: terminal, policy: windowOnly, at: t0))
        #expect(kinds(engine.observe(terminal, idleSeconds: 0, policy: windowOnly, at: t0)) == [.window])
        #expect(engine.wantsText(for: terminal, policy: screenOn, at: t0))
    }

    @Test func aHiddenWindowIsNeverWalkedForText() {
        let engine = CaptureEngine()
        #expect(!engine.wantsText(for: snapshot { $0.secureFocus = true }, policy: screenOn, at: t0))
        #expect(engine.wantsText(for: terminal, policy: screenOn, at: t0))
    }

    @Test func anAddressIsStoredWithoutItsQueryOrFragment() {
        var engine = CaptureEngine()
        let link = snapshot { $0.document = "https://app.example.com/cb?token=abc#access=xyz" }
        let kept = engine.observe(link, idleSeconds: 0, policy: screenOn, at: t0)
        #expect(kept?.activities.compactMap(\.document).allSatisfy { $0 == "https://app.example.com/cb" } == true)
        #expect(CaptureEngine.address("example.com/path") == "example.com/path")
        #expect(CaptureEngine.address("") == nil)
    }

}

struct FileCaptureTests {

    @Test func neverKeepsBuildOutputOrPasswordFiles() {
        var recorder = CaptureEngine()
        for path in ["/p/app/.git/index", "/p/app/.build/x.o", "/p/node_modules/a.js", "/d/passwords.txt"] {
            #expect(recorder.observe(.modify, path: path, policy: filesOn, at: t0) == nil, "\(path)")
        }
        #expect(recorder.observe(.create, path: "/d/notes.txt", policy: filesOn, at: t0) != nil)
    }

}

struct ActivityStoreTests {

    @Test func deletingOneSourceKeepsTheOtherAndDeletingEverythingKeepsNothing() throws {
        let store = try makeStore()
        var files = CaptureEngine()
        var screen = CaptureEngine()
        let file = files.observe(.modify, path: sourceFile, policy: filesOn, at: t0)
        let window = screen.observe(terminal, idleSeconds: 0, policy: screenOn, at: t0)
        try store.record(#require(file))
        try store.record(#require(window))
        try store.delete(.kind(.files, before: day(1)))
        #expect(try store.queries.activities(since: day(-1)).map(\.kind) == [.window, .text])
        try store.record(#require(file))
        try store.delete(.kind(.screen, before: day(1)))
        #expect(try store.queries.activities(since: day(-1)).map(\.kind) == [.file])
        try store.delete(.everything(before: nil))
        #expect(try store.queries.activities(since: day(-1)).isEmpty)
    }

}

struct RecordingStoreTests {
    private static let callsOn: [SourceKind: Bool] = [.call: true]

    private func callGrant(_ policy: CapturePolicy = CapturePolicy(switches: callsOn), at now: Date = t0)
        -> CaptureGrant?
    {
        policy.authorize(CaptureRequest(kind: .call, label: "com.brave.Browser", liveSession: true), at: now).grant
    }

    @Test func anOpenRecordingIsMarkedFailedOnTheNextStart() throws {
        let store = try makeStore()
        _ = try store.startRecording(app: "Brave", bundleID: "b", grant: #require(callGrant()))
        try store.closeInterruptedRecordings()
        #expect(try store.queries.recordings().map(\.state) == [.failed])
    }

    @Test func deletingCallsRemovesFinishedRowsAndAudioAndNeverTheCallBeingRecorded() throws {
        let store = try makeStore()
        let finished = try store.startRecording(app: "Brave", bundleID: "b", grant: #require(callGrant()))
        try store.finishRecording(finished.id)
        let live = try store.startRecording(app: "Brave", bundleID: "b", grant: #require(callGrant()))
        try store.delete(.kind(.call, before: day(1)))
        #expect(try store.queries.recordings().map(\.id) == [live.id])
        #expect(!FileManager.default.fileExists(atPath: finished.folder.path))
        #expect(FileManager.default.fileExists(atPath: live.folder.path))
        try store.finishRecording(live.id, error: "test")
        try store.delete(.everything(before: nil))
        #expect(try store.queries.recordings().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: live.folder.path))
    }

    @Test func theRecordingsFolderIsOwnerOnly() throws {
        let store = try makeStore()
        _ = try store.startRecording(app: "Brave", bundleID: "b", grant: #require(callGrant()))
        let folder = store.directory.appending(path: "recordings")
        #expect(try FileManager.default.attributesOfItem(atPath: folder.path)[.posixPermissions] as? Int == 0o700)
    }
}
