import SwiftUI
import WorkbenchCore

enum MachineEdit: Identifiable {
    /// A new machine whose page goes in `folder`, or in its template's folder when nil.
    case new(in: WorkObjectID?)
    case brief(HelperModel)

    var id: String {
        switch self {
        case .new(let folder): "new-\(folder ?? "")"
        case .brief(let helper): "brief-\(helper.machine.id)"
        }
    }
}

struct MachineSheet: View {
    let edit: MachineEdit
    let done: (Int64?) -> Void
    @Environment(Crew.self) private var crew
    @Environment(\.dismiss) private var dismiss
    @State private var template = MachineTemplate.team
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text(title).textStyle(.title2, weight: .bold)
            switch edit {
            case .new:
                Picker("Reads", selection: $template) {
                    ForEach(MachineTemplate.addable) { Text($0.reads ?? $0.role).tag($0) }
                }
                .pickerStyle(.radioGroup)
                Text(template.detail).foregroundStyle(.supporting)
                if lacksFollowable { Text(Crew.nothingToFollow).foregroundStyle(Tone.bad.color) }
                TextField("Name", text: $text, prompt: Text(template.name)).textFieldStyle(.roundedBorder)
            case .brief(let helper):
                TextEditor(text: $text).textStyle(.body).frame(minHeight: 180).border(.quaternary)
                Button("Try on past days first") {
                    let brief = text
                    Task { await helper.startTrial(brief: brief) }
                    dismiss()
                }
                .help(
                    "Reads up to \(HelperImprovement.trialDays) recent days with the new brief beside the current one. Nothing changes until you switch."
                )
                Text(
                    "A new brief is a new version. Its marks and trust start again; the old version's stay on the Usage page."
                )
                .foregroundStyle(.supporting)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(action: save) { Text(saveTitle) }.buttonStyle(.primary).keyboardShortcut(
                    .defaultAction
                ).disabled(lacksFollowable)
            }
        }
        .padding(Space.l)
        .zoomedWidth(480)
        .onAppear(perform: fill)
    }

    private var lacksFollowable: Bool {
        guard case .new = edit else { return false }
        return template.spec.needsFollowed && crew.factKeepers.isEmpty
    }

    private var title: String {
        switch edit {
        case .new: "Add a machine"
        case .brief(let helper): "\(helper.name)'s brief"
        }
    }

    private var saveTitle: String {
        switch edit {
        case .new: "Add"
        case .brief: "Save version"
        }
    }

    private func fill() {
        switch edit {
        case .new: text = ""
        case .brief(let helper): text = helper.spec.brief
        }
    }

    private func save() {
        switch edit {
        case .new(let folder): done(crew.create(from: template, name: text, in: folder))
        case .brief(let helper):
            crew.edit(helper, brief: text)
            done(nil)
        }
        dismiss()
    }
}
