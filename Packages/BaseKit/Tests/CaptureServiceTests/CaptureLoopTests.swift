import Foundation
import LocalSources
import Synchronization
import Testing
import WorkbenchCore

@testable import CaptureService

/// An Accessibility reader that only counts: every call is one cheap read or one text walk.
final class CountingReader: ScreenReading, Sendable {
    private let log = Mutex<[Bool]>([])
    private let window = Mutex(1)

    var calls: Int { log.withLock { $0.count } }
    var textWalks: Int { log.withLock { $0.filter { $0 }.count } }

    func openWindow(_ id: Int) { window.withLock { $0 = id } }

    func read(_ app: FrontApp, grant: CaptureGrant, withText: Bool) -> ScreenSnapshot {
        log.withLock { $0.append(withText) }
        return ScreenSnapshot(
            app: app.name, bundleID: app.bundleID, windowID: window.withLock { $0 }, title: "w",
            text: withText ? "body" : "")
    }
}

final class SwitchablePresence: PresenceSource, Sendable {
    private let current = Mutex(PresenceState.active)

    func set(_ state: PresenceState) { current.withLock { $0 = state } }
    func state(idleAfter: TimeInterval) -> PresenceState { current.withLock { $0 } }
}

struct CaptureLoopTests {
    static let start = Date(timeIntervalSince1970: 1_790_000_000)
    static let notes = FrontApp(pid: 1, name: "Notes", bundleID: "com.apple.Notes")
    static let policy = CapturePolicy(switches: [.screen: true, .screenText: true])

    private struct Rig {
        let loop: CaptureLoop
        let reader = CountingReader()
        let presence = SwitchablePresence()
        let store: Store

        init() throws {
            let clock = Mutex(CaptureLoopTests.start)
            store = try Store(
                directory: FileManager.default.temporaryDirectory.appending(path: "loop-\(UUID().uuidString)"),
                clock: { clock.withLock { $0 } })
            loop = CaptureLoop(store: store, presence: presence, reader: reader)
        }

        func tick(
            _ app: FrontApp = CaptureLoopTests.notes, policy: CapturePolicy = CaptureLoopTests.policy,
            after seconds: Double
        )
            async
        {
            let failure = await loop.capture(
                app, policy: policy, at: CaptureLoopTests.start.addingTimeInterval(seconds))
            #expect(failure == nil)
        }

        func rows(_ kind: Activity.Kind) throws -> Int {
            try store.queries.activities(since: .distantPast).filter { $0.kind == kind }.count
        }
    }

    @Test func anAppThatIsNotAllowedAndAnAppWithNoBundleIdAreNeverRead() async throws {
        var denying = Self.policy
        denying.denyList = [.screen: ["com.apple.Notes"]]
        for (app, policy) in [
            (Self.notes, denying), (FrontApp(pid: 2, name: "Ghost", bundleID: ""), Self.policy),
            (FrontApp(pid: 3, name: "1Password", bundleID: "com.1password.1password"), Self.policy),
        ] {
            let rig = try Rig()
            for second in stride(from: 0.0, to: 20, by: 2) { await rig.tick(app, policy: policy, after: second) }
            #expect(rig.reader.calls == 0, "\(app.name)")
            #expect(try rig.rows(.text) == 0 && rig.rows(.window) == 0)
        }
    }

    @Test func anAllowedAppIsReadOnceAndItsTextWalkedOnceWhileNothingChanges() async throws {
        let rig = try Rig()
        await rig.tick(after: 0)
        #expect(rig.reader.calls == 2 && rig.reader.textWalks == 1)
        await rig.tick(after: 2)
        #expect(rig.reader.calls == 3 && rig.reader.textWalks == 1)
        #expect(try rig.rows(.window) == 1 && rig.rows(.text) == 1)
    }

    @Test func idleCostsNothingAndWorkScalesWithChange() async throws {
        for state in [PresenceState.idle, .locked, .asleep, .screenOff] {
            let rig = try Rig()
            rig.presence.set(state)
            for second in stride(from: 0.0, to: 100, by: 2) { await rig.tick(after: second) }
            #expect(rig.reader.calls == 0, "\(state)")
            #expect(try rig.rows(.window) == 0 && rig.rows(.text) == 0, "\(state)")
        }
        let quiet = try Rig()
        for second in stride(from: 0.0, to: 200, by: 2) { await quiet.tick(after: second) }
        #expect(quiet.reader.textWalks == 4, "one walk now and one per minute, not one per tick")
        #expect(try quiet.rows(.text) == 1)
        let busy = try Rig()
        for (index, second) in stride(from: 0.0, to: 20, by: 2).enumerated() {
            busy.reader.openWindow(index / 2)
            await busy.tick(after: second)
        }
        #expect(busy.reader.textWalks == 5, "one walk for each of the 5 windows")
        #expect(try busy.rows(.window) == 5)
    }

    @Test func comingBackReadsAgainAndGoingAwayWritesTheIdleMarkerWithoutReading() async throws {
        let rig = try Rig()
        await rig.tick(after: 0)
        let before = rig.reader.calls
        rig.presence.set(.locked)
        await rig.tick(after: 2)
        #expect(rig.reader.calls == before)
        #expect(try rig.rows(.idle) == 1)
        rig.presence.set(.active)
        await rig.tick(after: 4)
        #expect(rig.reader.calls > before)
        #expect(try rig.rows(.active) == 1)
    }
}
