import SwiftUI
import WorkbenchCore

struct CriteriaSection: View {
    let helper: HelperModel
    @Environment(Crew.self) private var crew
    @State private var model: CriteriaModel

    init(helper: HelperModel) {
        self.helper = helper
        _model = State(initialValue: CriteriaModel(helper: helper))
    }

    var body: some View {
        Fold("Criteria · \(model.draft.rules.count) \(model.draft.rules.count == 1 ? "rule" : "rules")") {
            CriteriaBody(model: model, save: { model.save(into: crew) })
                .padding(.top, Space.m)
        }
        .textStyle(.headline)
    }
}

struct CriteriaBody: View {
    let model: CriteriaModel
    let save: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(
                "Your thesis, as rules. The model judges each rule with a quote; code makes the call by the table below."
            )
            .textStyle(.callout).foregroundStyle(.supporting)
            ForEach(model.draft.rules) { RuleRow(model: model, rule: $0) }
            if let form = model.form {
                RuleForm(
                    draft: Binding(get: { form }, set: { model.form = $0 }), commit: model.commitForm,
                    cancel: model.cancelForm)
            } else {
                Button("Add a rule", systemImage: "plus", action: model.add)
            }
            CombineTable(model: model)
            PreviewNote(preview: model.preview, isChanged: model.isChanged)
            if let blocker = model.blocker { Text(blocker).textStyle(.callout).foregroundStyle(Tone.bad.color) }
            HStack {
                Button("Save criteria", action: save).disabled(!model.isChanged || model.blocker != nil)
                Button("Discard changes", action: model.discard).disabled(!model.isChanged)
            }
        }
    }
}

private struct RuleRow: View {
    let model: CriteriaModel
    let rule: Rule

    var body: some View {
        HStack(spacing: Space.m) {
            Menu {
                ForEach(Rule.Role.allCases, id: \.self) { role in
                    Button(role.words) { model.setRole(role, of: rule) }
                }
            } label: {
                Text(rule.role.words).textStyle(.caption).padding(.horizontal, Space.s).padding(.vertical, 2)
                    .frame(width: 96).background(.quaternary, in: .capsule)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            Text(rule.summary).frame(maxWidth: .infinity, alignment: .leading)
            Button("Edit") { model.edit(rule) }.buttonStyle(.ghost).foregroundStyle(.linkText)
            Button("Remove") { model.remove(rule) }.buttonStyle(.ghost).foregroundStyle(.linkText)
        }
    }
}

private struct CombineTable: View {
    let model: CriteriaModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("How the call is made").textStyle(.headline)
            ForEach(model.draft.table, id: \.self) { Text($0).textStyle(.callout).foregroundStyle(.supporting) }
            HStack(spacing: Space.s) {
                Text("Points needed to be hot: \(model.draft.hotAt)")
                Button("−") { model.setHotAt(max(0, model.draft.hotAt - 1)) }
                Button("+") { model.setHotAt(min(10, model.draft.hotAt + 1)) }
            }
            .textStyle(.callout)
        }
    }
}

struct PreviewNote: View {
    let preview: CriteriaPreview
    let isChanged: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Preview on \(preview.rows.count) deals already read").textStyle(.headline)
            if !isChanged {
                Text("No unsaved change.").textStyle(.callout).foregroundStyle(.supporting)
            } else if preview.changed.isEmpty {
                Text("The call stays the same for every deal.").textStyle(.callout)
            }
            ForEach(preview.changed) { row in
                Text("\(row.title): \(row.was.rawValue) to \(row.now.rawValue)").textStyle(.callout)
            }
            if preview.unread > 0 {
                Text("Deals with a rule not read yet: \(preview.unread). They show unknown until read again.")
                    .textStyle(.callout).foregroundStyle(Tone.attention.color)
            }
        }
    }
}
