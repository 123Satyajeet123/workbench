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
    @Test func aNewTitleInTheSameWindowIsKeptAfterAMinuteButASpinnerGlyphIsNot() {
        var recorder = CaptureEngine()
        let policy = CapturePolicy(switches: [.screen: true])
        let titles = { (batch: ActivityBatch?) in batch?.activities.filter { $0.kind == .window }.map(\.title) ?? [] }
        #expect(
            titles(recorder.observe(snapshot { $0.title = "⠋ Fix login" }, idleSeconds: 0, policy: policy, at: t0)) == [
                "⠋ Fix login"
            ])
        #expect(
            titles(recorder.observe(snapshot { $0.title = "⠙ Fix login" }, idleSeconds: 0, policy: policy, at: t0 + 90))
                .isEmpty)
        #expect(
            titles(recorder.observe(snapshot { $0.title = "Review PR" }, idleSeconds: 0, policy: policy, at: t0 + 100))
                == ["Review PR"])
        #expect(
            titles(recorder.observe(snapshot { $0.title = "Deploy" }, idleSeconds: 0, policy: policy, at: t0 + 130))
                .isEmpty)
        #expect(
            titles(recorder.observe(snapshot { $0.title = "Deploy" }, idleSeconds: 0, policy: policy, at: t0 + 160))
                == ["Deploy"])
    }

    @Test func keepsNothingUntilTheScreenIsSwitchedOn() {
        var recorder = CaptureEngine()
        #expect(recorder.observe(terminal, idleSeconds: 0, policy: CapturePolicy(), at: t0) == nil)
        #expect(kinds(recorder.observe(terminal, idleSeconds: 0, policy: screenOn, at: t0)) == [.window, .text])
    }

    @Test func keepsNothingWhilePausedOrOffNotEvenMarkers() {
        var recorder = CaptureEngine()
        _ = recorder.observe(terminal, idleSeconds: 0, policy: screenOn, at: t0)
        var paused = screenOn
        paused.mode = .paused(until: day(1))
        #expect(recorder.observe(terminal, idleSeconds: 500, policy: paused, at: t0) == nil)
        var off = screenOn
        off.mode = .off
        #expect(recorder.observe(terminal, idleSeconds: 0, policy: off, at: t0) == nil)
    }

    @Test func aPlaceIsTheWindowAndItsDocumentNotTheTitle() {
        var recorder = CaptureEngine()
        _ = recorder.observe(terminal, idleSeconds: 0, policy: screenOn, at: t0)
        #expect(recorder.observe(snapshot { $0.title = "◑ claude" }, idleSeconds: 0, policy: screenOn, at: t0) == nil)
        let tab = snapshot { $0.document = "example.com/b" }
        let batch = recorder.observe(tab, idleSeconds: 0, policy: screenOn, at: t0)
        #expect(kinds(batch) == [.window])
        #expect(batch?.activities.first?.document == "example.com/b")
        let other = snapshot {
            $0.windowID = 2
            $0.text = "other"
        }
        #expect(kinds(recorder.observe(other, idleSeconds: 0, policy: screenOn, at: t0)) == [.window, .text])
    }

    @Test func textIsReadOnANewPlaceOrOncePerIntervalAndKeptOnlyWhenItChanged() {
        var recorder = CaptureEngine(textInterval: 60)
        #expect(recorder.wantsText(for: terminal, policy: screenOn, at: t0))
        _ = recorder.observe(terminal, idleSeconds: 0, policy: screenOn, at: t0)
        #expect(!recorder.wantsText(for: terminal, policy: screenOn, at: t0 + 30))
        #expect(recorder.wantsText(for: terminal, policy: screenOn, at: t0 + 60))
        #expect(recorder.wantsText(for: snapshot { $0.windowID = 2 }, policy: screenOn, at: t0 + 30))
        let changed = snapshot { $0.text = "hello world" }
        #expect(recorder.observe(changed, idleSeconds: 0, policy: screenOn, at: t0 + 10) == nil)
        #expect(kinds(recorder.observe(changed, idleSeconds: 0, policy: screenOn, at: t0 + 61)) == [.text])
        #expect(recorder.observe(changed, idleSeconds: 0, policy: screenOn, at: t0 + 200) == nil)
    }

    @Test func idleStopsCaptureAndMarksBothEdges() {
        var recorder = CaptureEngine(idleAfter: 120)
        _ = recorder.observe(terminal, idleSeconds: 0, policy: screenOn, at: t0)
        #expect(kinds(recorder.observe(terminal, idleSeconds: 200, policy: screenOn, at: t0 + 300)) == [.idle])
        let back = snapshot { $0.text = "new" }
        #expect(kinds(recorder.observe(back, idleSeconds: 0, policy: screenOn, at: t0 + 400)) == [.active, .text])
    }

    @Test func aDeniedAppOrAPrivatePlaceLeavesOnlyABlankMarker() {
        var recorder = CaptureEngine()
        var policy = screenOn
        policy.denyList = [.screen: ["com.apple.Terminal"]]
        #expect(
            recorder.observe(terminal, idleSeconds: 0, policy: policy, at: t0)?.activities == [
                Activity(at: t0, kind: .skipped)
            ])
        let incognito = snapshot {
            $0.windowID = 2
            $0.title = "News - Incognito"
        }
        #expect(kinds(recorder.observe(incognito, idleSeconds: 0, policy: screenOn, at: t0)) == [.skipped])
    }

    @Test func aSiteTheFounderDeniedIsHiddenWithItsSubdomainsAndOthersAreKept() {
        var recorder = CaptureEngine()
        var policy = screenOn
        policy.denyList = [.screen: ["linkedin.com"]]
        let denied = snapshot { $0.document = "www.linkedin.com/feed" }
        #expect(kinds(recorder.observe(denied, idleSeconds: 0, policy: policy, at: t0)) == [.skipped])
        let other = snapshot { $0.document = "example.com" }
        #expect(kinds(recorder.observe(other, idleSeconds: 0, policy: policy, at: t0)) == [.window, .text])
    }

    @Test func sleepAndWakeAreMarkedOnlyWhileCapturingAndTheNextWindowIsWrittenAgain() {
        var recorder = CaptureEngine()
        #expect(recorder.system(.sleep, policy: CapturePolicy(), at: t0) == nil)
        _ = recorder.observe(terminal, idleSeconds: 0, policy: screenOn, at: t0)
        #expect(kinds(recorder.system(.sleep, policy: screenOn, at: t0 + 10)) == [.sleep])
        #expect(kinds(recorder.system(.wake, policy: screenOn, at: t0 + 100)) == [.wake])
        #expect(kinds(recorder.observe(terminal, idleSeconds: 0, policy: screenOn, at: t0 + 102)) == [.window, .text])
    }
}

extension CaptureVerdict {
    var isHidden: Bool { if case .hide = self { true } else { false } }
}

private func hidden(_ screen: ScreenSnapshot, policy: CapturePolicy = screenOn) -> Bool {
    policy.verdict(for: screen, at: t0).isHidden
}

struct CaptureVerdictTests {
    @Test func hidesSensitivePlacesAndKeepsOrdinaryOnes() {
        #expect(!hidden(terminal))
        #expect(hidden(snapshot { $0.secureFocus = true }))
        #expect(hidden(snapshot { $0.bundleID = "com.apple.Health" }))
        #expect(hidden(snapshot { $0.title = "Reset your Password" }))
        #expect(hidden(snapshot { $0.title = "News - Private Browsing" }))
        #expect(hidden(snapshot { $0.document = "netbanking.hdfcbank.com/login" }))
        #expect(hidden(snapshot { $0.document = "https://www.paypal.com/myaccount" }))
        #expect(!hidden(snapshot { $0.document = "notpaypal.com.example.org/x" }))
        #expect(!hidden(snapshot { $0.document = "whiteboardcap.com/our-portfolio" }))
        #expect(!hidden(snapshot { $0.document = "file:///Users/me/Projects/" }))
    }

    @Test func aBrowserWhoseAddressIsUnknownIsHiddenAndAnAppWithoutADocumentIsKept() {
        let browser = snapshot { $0.bundleID = "com.google.Chrome" }
        #expect(hidden(browser))
        #expect(
            !hidden(
                snapshot {
                    $0.bundleID = "com.google.Chrome"
                    $0.document = "example.com"
                }))
        #expect(!hidden(terminal))
    }

    @Test func aDeniedSiteIsHiddenWhateverItsSpellingAndASimilarHostIsKept() {
        var policy = screenOn
        policy.denyList = [.screen: ["linkedin.com"]]
        for document in ["linkedin.com.", "https://WWW.LinkedIn.com./in/x", "www.linkedin.com/feed"] {
            #expect(hidden(snapshot { $0.document = document }, policy: policy), "\(document)")
        }
        #expect(!hidden(snapshot { $0.document = "notlinkedin.com/x" }, policy: policy))
    }

    @Test func aFolderOnTheDenyListHidesEveryFileUnderItAndASiblingFolderIsKept() {
        var policy = filesOn
        policy.denyList = [.files: ["/Users/me/Taxes"]]
        #expect(policy.verdict(forFile: "/Users/me/Taxes/2025/return.pdf", at: t0).isHidden)
        #expect(policy.verdict(forFile: "/Users/me/Taxes", at: t0).isHidden)
        #expect(!policy.verdict(forFile: "/Users/me/TaxesNotes/a.txt", at: t0).isHidden)
        #expect(!policy.verdict(forFile: "/Users/me/Notes/a.txt", at: t0).isHidden)
    }

    @Test func privateModeNeverGrantsWhileTheSourceIsSwitchedOffOrTheLabelIsDenied() {
        var policy = CapturePolicy(mode: .privateMode(until: day(1)), switches: [.call: false])
        let live = CaptureRequest(kind: .call, liveSession: true)
        #expect(policy.authorize(live, at: t0).denial == .sourceSwitchedOff)
        policy.switches = [.call: true]
        #expect(policy.authorize(live, at: t0).confirmation != nil)
        policy.denyList = [.call: ["x"]]
        #expect(
            policy.authorize(CaptureRequest(kind: .call, label: "x", liveSession: true), at: t0).denial
                == .labelDenied)
    }

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

    @Test func hidesFilesNamedForPasswordsOnly() {
        #expect(filesOn.verdict(forFile: "/Users/me/Documents/Passwords.txt", at: t0).isHidden)
        #expect(!filesOn.verdict(forFile: "/Users/me/Documents/notes.txt", at: t0).isHidden)
    }
}

struct FileCaptureTests {
    @Test func keepsNothingUntilFilesAreSwitchedOn() {
        var recorder = CaptureEngine()
        #expect(recorder.observe(.modify, path: sourceFile, policy: CapturePolicy(), at: t0) == nil)
        let batch = recorder.observe(.modify, path: sourceFile, policy: filesOn, at: t0)
        #expect(
            batch?.activities == [
                Activity(at: t0, kind: .file, title: "modify", document: URL(filePath: sourceFile).absoluteString)
            ])
    }

    @Test func neverKeepsBuildOutputOrPasswordFiles() {
        var recorder = CaptureEngine()
        for path in ["/p/app/.git/index", "/p/app/.build/x.o", "/p/node_modules/a.js", "/d/passwords.txt"] {
            #expect(recorder.observe(.modify, path: path, policy: filesOn, at: t0) == nil, "\(path)")
        }
        #expect(recorder.observe(.create, path: "/d/notes.txt", policy: filesOn, at: t0) != nil)
    }

    @Test func keepsOneRowPerFilePerMinute() {
        var recorder = CaptureEngine(fileWindow: 60)
        #expect(recorder.observe(.modify, path: sourceFile, policy: filesOn, at: t0) != nil)
        #expect(recorder.observe(.modify, path: sourceFile, policy: filesOn, at: t0 + 30) == nil)
        #expect(recorder.observe(.modify, path: sourceFile, policy: filesOn, at: t0 + 61) != nil)
    }
}

struct ActivityStoreTests {
    @Test func aFreshStoreHasTheOneSchemaWithTheActivityTable() throws {
        let store = try makeStore()
        let columns = try store.database.rows("PRAGMA table_info(activity)").compactMap { $0[1].string }
        #expect(columns == ["id", "ts", "kind", "app", "bundle_id", "title", "document", "text"])
    }

    @Test func keepsBatchesAndReadsThemBack() throws {
        let store = try makeStore()
        var recorder = CaptureEngine()
        let tab = snapshot { $0.document = "example.com" }
        let batch = recorder.observe(tab, idleSeconds: 0, policy: screenOn, at: t0)
        try store.record(#require(batch))
        let kept = try store.queries.activities(since: day(-1))
        #expect(kept.map(\.kind) == [.window, .text])
        #expect(kept.allSatisfy { $0.document == "example.com" })
        #expect(kept.last?.text == "hello")
    }

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

    @Test func deletingOneRowKeepsTheRest() throws {
        let store = try makeStore()
        var recorder = CaptureEngine()
        let batch = recorder.observe(terminal, idleSeconds: 0, policy: screenOn, at: t0)
        try store.record(#require(batch))
        let window = try #require(try store.queries.activities(since: day(-1)).first { $0.kind == .window }?.id)
        try store.delete(.activities(ActivityFilter(id: window)))
        #expect(try store.queries.activities(since: day(-1)).map(\.kind) == [.text])
    }

    @Test func theSchemaRefusesAMarkerThatCarriesContent() throws {
        let store = try makeStore()
        #expect(throws: (any Error).self) {
            try store.database.run(
                "INSERT INTO activity(ts, kind, app, bundle_id, title, text) VALUES ('t', 'idle', '', '', '', 'secret')"
            )
        }
        #expect(throws: (any Error).self) {
            try store.database.run(
                "INSERT INTO activity(ts, kind, app, bundle_id, title) VALUES ('t', 'keystroke', 'a', 'b', 'c')")
        }
        try store.database.run("INSERT INTO activity(ts, kind, app, bundle_id, title) VALUES ('t', 'idle', '', '', '')")
    }
}

struct RecordingStoreTests {
    private static let callsOn: [SourceKind: Bool] = [.call: true]

    private func callGrant(_ policy: CapturePolicy = CapturePolicy(switches: callsOn), at now: Date = t0)
        -> CaptureGrant?
    {
        policy.authorize(CaptureRequest(kind: .call, label: "com.brave.Browser", liveSession: true), at: now).grant
    }

    @Test func aCallIsAllowedOnlyWhenSwitchedOnAndNotWhilePausedOffOrDenied() {
        #expect(callGrant(CapturePolicy()) == nil)
        #expect(callGrant() != nil)
        #expect(callGrant(CapturePolicy(mode: .off, switches: Self.callsOn)) == nil)
        #expect(callGrant(CapturePolicy(mode: .paused(until: day(1)), switches: Self.callsOn)) == nil)
        #expect(callGrant(CapturePolicy(switches: Self.callsOn, denyList: [.call: ["com.brave.Browser"]])) == nil)
        let privateHour = CapturePolicy(mode: .privateMode(until: day(1)), switches: Self.callsOn)
        guard
            case .confirm = privateHour.authorize(
                CaptureRequest(kind: .call, label: "com.brave.Browser", liveSession: true), at: t0)
        else {
            Issue.record("private mode must ask")
            return
        }
    }

    @Test func onlyACallGrantStartsARecordingAndTheRowClosesOnce() throws {
        let store = try makeStore()
        let screen = try #require(
            CapturePolicy(switches: [.screen: true]).authorize(CaptureRequest(kind: .screen), at: t0).grant)
        #expect(throws: StoreError.grantForOtherKind(granted: .screen, requested: .call)) {
            try store.startRecording(app: "Brave", bundleID: "b", grant: screen)
        }
        let recording = try store.startRecording(app: "Brave", bundleID: "b", grant: #require(callGrant()))
        #expect(FileManager.default.fileExists(atPath: recording.folder.path))
        try store.finishRecording(recording.id)
        try store.finishRecording(recording.id, error: "late")
        let saved = try #require(try store.queries.recordings().first)
        #expect(saved.state == .saved && saved.error == nil && saved.endedAt != nil)
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
