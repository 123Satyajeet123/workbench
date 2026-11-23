import AppKit
import Foundation
import Observation
import WorkbenchCore

/// What the founder can do with an item, drafts first: a message the model drafts and the founder copies and sends
/// themselves, or a reminder in their Reminders app. Each act happens only on the founder's click and is logged.
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
    private(set) var problem: String?

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let founder: () -> String
    @ObservationIgnored private let makeModel: (ModelChoice) -> RecordedModel
    @ObservationIgnored private let reminders: ReminderList
    @ObservationIgnored private let pasteboard: (String) -> Void

    init(
        store: Store, founder: @escaping () -> String, makeModel: ((ModelChoice) -> RecordedModel)? = nil,
        reminders: ReminderList = AppleReminders(), pasteboard: ((String) -> Void)? = nil
    ) {
        self.store = store
        self.founder = founder
        self.makeModel = makeModel ?? { $0.model(store: store) }
        self.reminders = reminders
        self.pasteboard =
            pasteboard ?? {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString($0, forType: .string)
            }
    }

    /// The model drafts; nothing leaves until the founder copies it.
    func draft(_ item: Item, from machine: Machine) async {
        guard let id = item.id else { return }
        drafting = id
        defer { drafting = nil }
        do {
            let drafter = Drafter(model: makeModel(try ModelChoice.saved(in: store)))
            let (draft, _) = try await drafter.draft(item, from: machine, founder: founder())
            self.draft = Draft(item: id, task: machine.task, to: draft.to, text: draft.text)
            problem = nil
        } catch {
            problem = "Could not draft a message: \(error.localizedDescription)"
        }
    }

    /// The founder's click: the edited draft goes to the clipboard, for the founder to paste and send.
    func copy(_ draft: Draft) {
        pasteboard(draft.text)
        attempt("log the copy") {
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
            attempt("add the reminder") {
                try reminders.add(title: title, notes: "“\(item.quote)” — \(machine.name), \(item.day)")
                try store.log("make_reminder", target: machine.task, detail: ["item": String(id), "title": title])
                notice = "Added “\(title)” to Reminders."
            }
        case .blocked:
            remindersBlocked = true
        case .failed(let reason):
            problem = "macOS did not allow Reminders: \(reason)"
        }
    }

    func dismiss() {
        notice = nil
        problem = nil
        remindersBlocked = false
    }

    private func attempt(_ step: String, _ work: () throws -> Void) {
        do {
            try work()
        } catch {
            problem = "Could not \(step): \(error.localizedDescription)"
        }
    }
}
