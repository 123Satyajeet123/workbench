import CaptureService
import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

@MainActor
struct CaptureSettingsTests {
    @Test func switchesAndModeAreSavedAsTheStoredPolicy() throws {
        let store = try scratchStore()
        let settings = try captureSettings(over: store)
        #expect(try !store.currentPolicy().isEnabled(.screen))
        for kind in [SourceKind.screen, .screenText, .files] {
            settings.set(kind, on: true)
            #expect(try store.currentPolicy().isEnabled(kind))
            #expect(settings.isOn(kind))
        }
        settings.mode = .paused
        guard case .paused = try store.currentPolicy().mode else {
            Issue.record("not paused")
            return
        }
        settings.mode = .on
        #expect(try store.currentPolicy().mode == .on)
    }

    @Test func aFreshSettingsShowsTheStoredPolicyWithoutWritingIt() throws {
        let store = try scratchStore()
        try store.savePolicy(CapturePolicy(mode: .off, switches: [.screen: true]))
        let settings = try captureSettings(over: store)
        #expect(settings.mode == .off)
        #expect(settings.isOn(.screen))
        #expect(!settings.isOn(.files))
        #expect(settings.status == .off)
        #expect(try store.queries.count(of: .consent) == 1)
    }

    @Test func theDenyListTakesAWebsiteSavesItAndRefusesOtherText() throws {
        let store = try scratchStore()
        let settings = try captureSettings(over: store)
        #expect(settings.deny("https://www.LinkedIn.com/feed"))
        #expect(!settings.deny("not a place"))
        #expect(try store.currentPolicy().denyList[.screen] == ["linkedin.com"])
        let reopened = try captureSettings(over: store)
        #expect(reopened.denyList.map(\.label) == ["linkedin.com"])
        reopened.allow(try #require(reopened.denyList.first))
        #expect(try store.currentPolicy().denyList[.screen] == nil)
    }

    @Test func theLogShowsTodaysKeptWindowsAndDeleteRemovesTheRow() throws {
        let store = try scratchStore()
        var engine = CaptureEngine()
        let snapshot = ScreenSnapshot(app: "Terminal", bundleID: "t", windowID: 1, title: "claude", text: "x")
        let batch = engine.observe(snapshot, idleSeconds: 0, policy: CapturePolicy(switches: [.screen: true]), at: .now)
        try store.record(#require(batch))
        let settings = try captureSettings(over: store)
        #expect(settings.log.map(\.summary) == ["Terminal: claude"])
        settings.delete(try #require(settings.log.first))
        #expect(settings.log.isEmpty)
        #expect(try store.queries.activities(since: .distantPast).isEmpty)
    }
}
