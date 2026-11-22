import AppKit
import Foundation
import Observation
import WorkbenchCore

@Observable
final class ActionsModel {
    struct Draft: Identifiable, Equatable {
        let item: Int64
        let task: String
        var to: String
        var text: String
        var id: Int64 { item }
    }

    var draft: Draft?
    private(set) var drafting: Int64?
    private(set) var notice: String?
    private(set) var remindersBlocked = false
    let problems = ProblemSlot()
    var problem: String? { problems.text }

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let founder: () -> String
    @ObservationIgnored private let makeModel: ModelMaker
    @ObservationIgnored private let reminders: ReminderList
    @ObservationIgnored private let pasteboard: (String) -> Void

    init(
        store: Store, founder: @escaping () -> String, makeModel: ((ModelChoice) -> RecordedModel)? = nil,
        reminders: ReminderList = AppleReminders(), pasteboard: ((String) -> Void)? = nil
    ) {
        self.store = store
        self.founder = founder
        self.makeModel = ModelMaker(store: store, make: makeModel)
        self.reminders = reminders
        self.pasteboard =
            pasteboard ?? {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString($0, forType: .string)
            }
    }

    func draft(_ item: Item, from machine: Machine) async {
        guard let id = item.id else { return }
        drafting = id
        defer { drafting = nil }
        await problems.attempt("draft a message", clearing: true) {
            let drafter = Drafter(model: try makeModel.current())
            let (draft, _) = try await drafter.draft(item, from: machine, founder: founder())
            self.draft = Draft(item: id, task: machine.task, to: draft.to, text: draft.text)
        }
    }

    func copy(_ draft: Draft) {
        pasteboard(draft.text)
        problems.attempt("log the copy") {
            try store.log(
                "copy_draft", target: draft.task, detail: ["item": String(draft.item), "to": draft.to])
        }
        notice = draft.to.isEmpty ? "Draft copied." : "Draft for \(draft.to) copied. Paste it where you send it."
        self.draft = nil
    }

    func remind(_ item: Item, from machine: Machine, title: String) async {
        guard let id = item.id else { return }
        switch await reminders.authorize() {
        case .allowed:
            remindersBlocked = false
            problems.attempt("add the reminder") {
                try reminders.add(title: title, notes: "“\(item.quote)” — \(machine.name), \(item.day)")
                try store.log("make_reminder", target: machine.task, detail: ["item": String(id), "title": title])
                notice = "Added “\(title)” to Reminders."
            }
        case .blocked:
            remindersBlocked = true
        case .failed(let reason):
            problems.show("macOS did not allow Reminders: \(reason)")
        }
    }

    func dismiss() {
        notice = nil
        problems.dismiss()
        remindersBlocked = false
    }
}
