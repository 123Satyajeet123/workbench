import SwiftUI
import WorkbenchCore

struct ItemActions: View {
    let model: HelperModel
    let item: Item
    @Environment(ActionsModel.self) private var actions

    var body: some View {
        if actions.drafting == item.id {
            ProgressView().controlSize(.small)
        } else {
            Menu("Act on this", systemImage: "ellipsis.circle") {
                Button("Draft a message…") { Task { await actions.draft(item, from: model.machine) } }
                Button("Add to Reminders") {
                    Task { await actions.remind(item, from: model.machine, title: item[model.spec.title]) }
                }
            }
            .labelStyle(.iconOnly).menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .disabled(item.state == .rejected)
        }
    }
}

struct DraftSheet: View {
    @State var draft: ActionsModel.Draft
    @Environment(ActionsModel.self) private var actions
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(draft.to.isEmpty ? "Draft" : "Draft for \(draft.to)").textStyle(.headline)
            TextEditor(text: $draft.text).frame(minWidth: 420, minHeight: 140).textStyle(.body)
            Text("Workbench never sends it. Copy it, then paste it where you send it.").textStyle(.callout)
                .foregroundStyle(.supporting)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Copy") { actions.copy(draft) }.buttonStyle(.primary).keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.l)
    }
}
