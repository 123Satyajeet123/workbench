import Foundation
import LocalSources
import Testing
import WorkbenchCore

@testable import WorkbenchUI

@MainActor private final class FakeControls: CallControls {
    var recordingApp: String?
    var callsAllowed = true
    var isPrivate = false
    var started: [(String, Bool)] = []
    var stops = 0

    func record(_ app: AudioApp, confirmed: Bool) {
        started.append((app.bundleID, confirmed))
        recordingApp = app.bundleID
    }

    func stopRecording() {
        stops += 1
        recordingApp = nil
    }
}

@MainActor struct CallWatcherTests {
    private let zoom = AudioApp(bundleID: "us.zoom.xos", name: "zoom.us", processes: [1])
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func watcher(_ controls: FakeControls, store: Store, said: @escaping (String) -> Void = { _ in })
        -> CallWatcher
    {
        CallWatcher(
            store: store, controls: controls, announce: { title, _ in said(title) },
            identify: { CallSource(service: $0.name == "zoom.us" ? "Zoom" : $0.name) })
    }

    private func run(_ watcher: CallWatcher, _ apps: [AudioApp], from: TimeInterval, to: TimeInterval) {
        for second in stride(from: from, through: to, by: 2) {
            watcher.update(listening: apps, at: start.addingTimeInterval(second))
        }
    }

    @Test func aNewCallIsOfferedOnceAndRecordingItStopsWhenTheCallEnds() throws {
        let controls = FakeControls()
        var titles: [String] = []
        let watcher = watcher(controls, store: try scratchStore()) { titles.append($0) }
        run(watcher, [zoom], from: 0, to: 4)
        #expect(watcher.offer == nil)
        run(watcher, [zoom], from: 6, to: 20)
        #expect(watcher.offer?.source.label == "Zoom" && titles == ["Record this Zoom call?"])

        watcher.record()
        #expect(watcher.offer == nil && controls.started.map(\.0) == ["us.zoom.xos"])
        run(watcher, [], from: 22, to: 40)
        #expect(controls.stops == 1)
    }

    @Test func notNowLeavesTheCallAloneAndTheOfferGoesWhenTheCallEnds() throws {
        let controls = FakeControls()
        let watcher = watcher(controls, store: try scratchStore())
        run(watcher, [zoom], from: 0, to: 8)
        #expect(watcher.offer != nil)
        run(watcher, [], from: 10, to: 30)
        #expect(watcher.offer == nil && controls.started.isEmpty && controls.stops == 0)
    }

    @Test func anAppMarkedAlwaysIsRecordedOnItsOwnButNotInPrivateMode() throws {
        let store = try scratchStore()
        let controls = FakeControls()
        let first = watcher(controls, store: store)
        run(first, [zoom], from: 0, to: 8)
        first.recordAlways()
        run(first, [], from: 10, to: 30)

        var titles: [String] = []
        let later = watcher(controls, store: store) { titles.append($0) }
        #expect(later.always == ["us.zoom.xos": "zoom.us"])
        run(later, [zoom], from: 100, to: 108)
        #expect(later.offer == nil && controls.started.count == 2 && titles == ["Recording your Zoom call"])
        run(later, [], from: 110, to: 130)

        controls.isPrivate = true
        run(later, [zoom], from: 200, to: 208)
        #expect(later.offer != nil && controls.started.count == 2)
        later.record()
        #expect(controls.started.last?.1 == true)
    }

    @Test func aCallAlreadyBeingRecordedOrCallsSwitchedOffAreLeftAlone() throws {
        let controls = FakeControls()
        controls.recordingApp = "com.google.Chrome"
        let watcher = watcher(controls, store: try scratchStore())
        run(watcher, [zoom], from: 0, to: 8)
        #expect(watcher.offer == nil)

        let off = FakeControls()
        off.callsAllowed = false
        let quiet = self.watcher(off, store: try scratchStore())
        run(quiet, [zoom], from: 0, to: 20)
        #expect(quiet.offer == nil && off.started.isEmpty)
    }
}
