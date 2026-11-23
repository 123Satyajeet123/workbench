import CaptureService
import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// Settings › Capture › Delete: the WhatsApp control erases what Workbench kept of that kind, and no other kind.
@MainActor @Suite struct SettingsDeleteTests {
    private let noon: Date = {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_790_000_000))!
    }()

    @Test func deletingWhatsAppDataEmptiesItsLinesAndLeavesOtherKinds() async throws {
        let now = noon
        let store = try scratchStore(clock: { now })
        let capture = try CaptureService(store: store)
        let source = try WhatsAppSource(
            store: store, capture: capture, task: HelperSpec.team.task, founder: { "Kabir" },
            container: try whatsApp(at: now))
        try source.loadGroups()
        try source.choose(try #require(source.groups.first))
        let day = WorkDay(containing: now)
        #expect(try await source.evidence(on: day).lines.isEmpty == false)
        try store.record(try keptWindow(at: now))
        #expect(try store.queries.activities(since: .distantPast).isEmpty == false)

        let settings = CaptureSettings(service: capture)
        settings.deleteAll(.whatsapp)

        #expect(settings.failure == nil)
        let chat = try #require(source.chats.first)
        #expect(try store.queries.currentLines(in: [chat.container], from: day.start, to: day.end).isEmpty)
        #expect(try store.queries.activities(since: .distantPast).isEmpty == false, "screen data stays")
    }

    @Test func deletingAnotherKindLeavesTheWhatsAppLines() async throws {
        let now = noon
        let store = try scratchStore(clock: { now })
        let capture = try CaptureService(store: store)
        let source = try WhatsAppSource(
            store: store, capture: capture, task: HelperSpec.team.task, founder: { "Kabir" },
            container: try whatsApp(at: now))
        try source.loadGroups()
        try source.choose(try #require(source.groups.first))
        let day = WorkDay(containing: now)
        _ = try await source.evidence(on: day)

        CaptureSettings(service: capture).deleteAll(.screen)

        let chat = try #require(source.chats.first)
        #expect(try store.queries.currentLines(in: [chat.container], from: day.start, to: day.end).isEmpty == false)
    }

    private func keptWindow(at now: Date) throws -> ActivityBatch {
        var engine = CaptureEngine()
        let snapshot = ScreenSnapshot(app: "Brave", bundleID: "b", windowID: 1, title: "w", text: "")
        let batch = engine.observe(
            snapshot, presence: .active, policy: CapturePolicy(switches: [.screen: true]), at: now)
        return try #require(batch)
    }
}
