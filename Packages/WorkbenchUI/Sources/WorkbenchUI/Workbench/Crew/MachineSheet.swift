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

/// What a new machine starts from: nothing but a source and a job, or a gallery template.
enum MachineStart: Identifiable, Equatable {
    case blank
    case template(GalleryTemplate)

    var id: String {
        switch self {
        case .blank: ""
        case .template(let template): template.id
        }
    }

    static let all = [MachineStart.blank] + GalleryTemplate.all.filter { $0.machine != nil }.map(Self.template)
}

struct MachineSheet: View {
    let edit: MachineEdit
    let done: (Int64?) -> Void
    @Environment(Crew.self) private var crew
    @Environment(\.dismiss) private var dismiss
    @State private var start: MachineStart?
    @State private var text = ""
    @State private var sourceKey: String?
    @State private var job = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text(title).textStyle(.title2, weight: .bold)
            switch edit {
            case .new:
                ScrollView {
                    ChoiceList(items: MachineStart.all, chosen: $start) { StartLabel(start: $0) }
                }
                .frame(maxHeight: 360)
                if lacksFollowable { Text(Crew.nothingToFollow).foregroundStyle(Tone.bad.color) }
                TextField("Name", text: $text, prompt: Text(template?.name ?? "Name")).textFieldStyle(.roundedBorder)
                if start == .blank { blankFields }
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
                ).disabled(lacksFollowable || !canAdd)
            }
        }
        .padding(Space.l)
        .zoomedWidth(480)
        .onAppear(perform: fill)
    }

    private var template: MachineTemplate? {
        if case .template(let item)? = start { item.machine } else { nil }
    }

    private var blankFields: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Picker("Reads", selection: $sourceKey) {
                Text("Choose what it reads").tag(String?.none)
                ForEach(Crew.blankMachineSources, id: \.key) { Text($0.name).tag(Optional($0.key)) }
            }
            TextField("Its job, in one sentence", text: $job).textFieldStyle(.roundedBorder)
        }
    }

    private var source: SourceDescriptor? { Crew.blankMachineSources.first { $0.key == sourceKey } }

    /// Whether the person gave what the chosen start needs: a template, or a name, a source and a job.
    private var canAdd: Bool {
        guard isNew else { return true }
        switch start {
        case nil: return false
        case .blank?: return text.cleaned != nil && source != nil && job.cleaned != nil
        case .template?: return true
        }
    }

    private var isNew: Bool {
        if case .new = edit { true } else { false }
    }

    private var lacksFollowable: Bool {
        guard case .new = edit, let template else { return false }
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

    private func created(in folder: WorkObjectID?) -> Int64? {
        if let template { return crew.create(from: template, name: text, in: folder) }
        guard let source, let name = text.cleaned else { return nil }
        return crew.createBlank(over: source, job: job, name: name, in: folder)
    }

    private func save() {
        switch edit {
        case .new(let folder):
            done(created(in: folder))
        case .brief(let helper):
            crew.edit(helper, brief: text)
            done(nil)
        }
        dismiss()
    }
}

private struct StartLabel: View {
    let start: MachineStart

    var body: some View {
        switch start {
        case .blank:
            HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                Image(systemName: "plus.square.dashed").foregroundStyle(.iconTint).frame(width: Space.l)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.xs / 2) {
                    Text("Blank machine").textStyle(.headline)
                    Text("You name it, choose what it reads and write its job.").textStyle(.callout)
                        .foregroundStyle(.supporting).fixedSize(horizontal: false, vertical: true)
                }
            }
        case .template(let template): GalleryItemLabel(template: template)
        }
    }
}
