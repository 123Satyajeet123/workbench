import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

private final class FakeReminders: ReminderList {
    var access = SystemAccess.allowed
    var added: [(title: String, notes: String)] = []

    func authorize() async -> SystemAccess { access }
    func add(title: String, notes: String) throws { added.append((title, notes)) }
}

@Suite struct ActionTests {
    private let reply = #"{"to":"Asha","text":"Great work on the login API! Can you share the PR link?"}"#

    private func setup() async throws -> (ActionsModel, Store, Item, ScriptedModel, FakeReminders, Box) {
        let store = try scratchStore()
        let today = WorkDay(containing: store.clock())
        let model = RecordedModel(ScriptedModel(#"{"items":[]}"#), store: store)
        let (_, run) = try await model.generate(
            Nothing.self, schema: .object([]), task: HelperSpec.team.task, instructions: "v1", input: "x")
        try store.saveReading(
            .init(
                items: [
                    Item(
                        task: HelperSpec.team.task, day: today, scope: "team", source: .whatsapp, citeFirst: 11,
                        citeLast: 11, start: store.clock(), end: store.clock(),
                        fields: ["person": "Asha", "kind": "done", "text": "Login API"], quote: "login API done",
                        run: run)
                ], dropped: 0, run: run),
            of: .team, day: today, scope: "team",
            grant: CapturePolicy(switches: [.whatsapp: true], allowList: [.whatsapp: ["team"]])
                .authorize(CaptureRequest(kind: .whatsapp, label: "team"), at: store.clock()).grant!)
        let item = try #require(try store.queries.items(of: HelperSpec.team.task, day: today, scope: "team").first)
        let scripted = ScriptedModel(reply)
        let reminders = FakeReminders()
        let clipboard = Box()
        let actions = ActionsModel(
            store: store, founder: { "Kabir" }, makeModel: { _ in RecordedModel(scripted, store: store) },
            reminders: reminders, pasteboard: { clipboard.text = $0 })
        return (actions, store, item, scripted, reminders, clipboard)
    }

    final class Box { var text: String? }

    @Test func aDraftIsOnlyWrittenUntilTheFounderCopiesIt() async throws {
        let (actions, store, item, scripted, _, clipboard) = try await setup()
        await actions.draft(item, from: .test(.team, "Pip"))
        let input = try #require(scripted.inputs.withLock { $0.first })
        #expect(input.contains("- person: Asha") && input.contains(#"Quote: "login API done""#))
        var draft = try #require(actions.draft)
        #expect(draft.to == "Asha")
        #expect(clipboard.text == nil, "drafting copies nothing")
        #expect(try store.queries.actions().isEmpty, "drafting logs nothing")
        #expect(try store.queries.runs().contains { $0.task == Drafter.task }, "the draft call is on Runs")

        draft.text = "Nice work, Asha. PR link?"
        actions.copy(draft)
        #expect(clipboard.text == "Nice work, Asha. PR link?")
        #expect(actions.draft == nil)
        let logged = try #require(try store.queries.actions().first)
        #expect(logged.kind == "copy_draft" && logged.detail["to"] == "Asha")
    }

    @Test func aReminderIsMadeOnlyWhenMacOSAllowsItAndIsLogged() async throws {
        let (actions, store, item, _, reminders, _) = try await setup()
        reminders.access = .blocked
        await actions.remind(item, from: .test(.team, "Pip"), title: "Login API")
        #expect(actions.remindersBlocked && reminders.added.isEmpty)
        #expect(try store.queries.actions().isEmpty)

        reminders.access = .allowed
        await actions.remind(item, from: .test(.team, "Pip"), title: "Login API")
        #expect(!actions.remindersBlocked)
        #expect(reminders.added.map(\.title) == ["Login API"])
        #expect(reminders.added.first?.notes.contains("login API done") == true)
        #expect(try store.queries.actions().map(\.kind) == ["make_reminder"])
    }
}
