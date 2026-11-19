import CaptureService
import Foundation
import Synchronization
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// Atlas, the work-context machine: typed facts with a topic that stays the same across readings.
@Suite struct ContextMachineTests {
    private let noon: Date = {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_790_000_000))!
    }()

    @Test func theSecondReadingIsShownTheTopicsItUsedAndAFactWithNoTopicIsDropped() async throws {
        let now = noon
        let store = try scratchStore(clock: { now })
        let container = try whatsApp(at: noon)
        let source = try WhatsAppSource(
            store: store, capture: try CaptureService(store: store), task: "work.context-1", founder: { "Kabir" },
            container: container)
        try source.loadGroups()
        try source.choose(try #require(source.groups.first { $0.jid == teamJID }))
        let model = KeyedModel([
            "You keep a founder's work context":
                #"{"items":[{"kind":"status","text":"Login API is done","who":"Asha","topic":"Login API","due":"","stance":"said","cite":11,"quote":"login API done"},{"kind":"question","text":"No topic","who":"","topic":" ","due":"","stance":"said","cite":11,"quote":"login API done"}],"closes":[]}"#
        ])
        var spec = HelperSpec.context
        spec.task = "work.context-1"
        let atlas = HelperModel(
            machine: Machine(id: 1, name: "Atlas", template: HelperSpec.context.task, spec: spec, state: .active),
            source: source, store: store, makeModel: { _ in RecordedModel(model, store: store) },
            notifier: FakeNotifier())
        await atlas.read()
        #expect(atlas.items.map { $0["topic"] } == ["Login API"])
        #expect(atlas.phase == .read(kept: 1, dropped: 1), "a fact needs a topic")

        try addMessage(30, "payments blocked on keys", at: noon.addingTimeInterval(600), to: container)
        model.replies.withLock {
            $0["You keep a founder's work context"] =
                #"{"items":[{"kind":"status","text":"Payments are blocked on keys","who":"Asha","topic":"Login API","due":"","stance":"said","cite":30,"quote":"payments blocked on keys"}],"closes":[]}"#
        }
        await atlas.read()
        let input = try #require(model.inputs.withLock { $0.last })
        #expect(input.contains("Topics: Login API"), "the topic it used before is offered for reuse")
        #expect(atlas.items.map(\.quote) == ["login API done", "payments blocked on keys"])
    }

    @Test func aCommitmentFromYesterdayStaysOpenUntilALineTodayClosesIt() async throws {
        let clock = Mutex(noon)
        let store = try scratchStore(clock: { clock.withLock { $0 } })
        let container = try whatsApp(at: noon)
        let source = try WhatsAppSource(
            store: store, capture: try CaptureService(store: store), task: "work.context-1", founder: { "Kabir" },
            container: container)
        try source.loadGroups()
        try source.choose(try #require(source.groups.first { $0.jid == teamJID }))
        let model = KeyedModel([
            "You keep a founder's work context":
                #"{"items":[{"kind":"commitment","text":"Ship the login API","who":"Asha","topic":"Login API","due":"","stance":"said","cite":11,"quote":"login API done"}],"closes":[]}"#
        ])
        var spec = HelperSpec.context
        spec.task = "work.context-1"
        let atlas = HelperModel(
            machine: Machine(id: 1, name: "Atlas", template: HelperSpec.context.task, spec: spec, state: .active),
            source: source, store: store, makeModel: { _ in RecordedModel(model, store: store) },
            notifier: FakeNotifier())
        await atlas.read()
        #expect(atlas.open.map { $0["text"] } == ["Ship the login API"])

        let tomorrow = noon.addingTimeInterval(86_400)
        clock.withLock { $0 = tomorrow }
        try addMessage(40, "login shipped to everyone", at: tomorrow, to: container)
        model.replies.withLock {
            $0["You keep a founder's work context"] =
                #"{"items":[],"closes":[{"handle":"F1","outcome":"kept","cite":40,"quote":"login shipped"}]}"#
        }
        atlas.show(WorkDay(containing: tomorrow))
        await atlas.read()
        let input = try #require(model.inputs.withLock { $0.last })
        #expect(input.contains("F1 ("), "yesterday's open commitment is shown by handle")
        #expect(atlas.open.isEmpty)
        #expect(atlas.closed.map { $0.closed?.outcome } == ["kept"])

        atlas.reopen(try #require(atlas.closed.first))
        #expect(atlas.open.count == 1 && atlas.closed.isEmpty, "the founder can undo a wrong close")
    }
}
