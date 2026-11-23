import SwiftUI
import WorkbenchCore

/// The sidebar: plain rows in the order `SidebarPlan` gives, as the system draws a sidebar. A machine has a small dot
/// for what it is doing. The Machines header opens the Crew page; its + adds a machine.
struct Sidebar: View {
    let sections: [SidebarSection]
    @Binding var selection: SidebarSelection
    @Environment(Crew.self) private var crew
    @Environment(TeamCatalogModel.self) private var catalog
    @State private var editing: MachineEdit?
    @State private var deleting: HelperModel?

    var body: some View {
        List(selection: listSelection) {
            ForEach(sections) { section in
                Section {
                    ForEach(section.rows) { row in
                        label(of: row).tag(row.selection).contextMenu { menu(for: row) }
                    }
                } header: {
                    if let title = section.header { header(title) }
                }
            }
        }
        .listStyle(.sidebar)
        .sheet(item: $editing) { edit in
            MachineSheet(edit: edit) { id in if let id { selection = .machine(id) } }
        }
        .confirmationDialog(
            "Delete \(deleting?.name ?? "")?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { helper in
            Button("Delete \(helper.name)", role: .destructive) { crew.delete(helper) }
        } message: { helper in
            Text(
                "Its \(helper.spec.itemsNoun), your marks on them and its settings are deleted. Its runs stay in Settings › Advanced."
            )
        }
    }

    private var listSelection: Binding<SidebarSelection?> {
        Binding(get: { selection }, set: { if let page = $0 { selection = page } })
    }

    private func header(_ title: String) -> some View {
        HStack {
            Button(title) { selection = .crew }.buttonStyle(.plain)
            Spacer()
            Button("Add a machine", systemImage: "plus") { editing = .new }
                .labelStyle(.iconOnly).buttonStyle(.plain)
                .help("Add a machine")
        }
    }

    @ViewBuilder private func label(of row: SidebarRow) -> some View {
        switch row {
        case .page(let page, let count):
            Label(page.title, systemImage: page.symbol).badge(count)
        case .machine(let machine):
            Label {
                Text(machine.name).lineLimit(1)
            } icon: {
                StatusDot(status: machine.status)
            }
            .accessibilityValue(machine.status.words)
        }
    }

    @ViewBuilder private func menu(for row: SidebarRow) -> some View {
        if case .machine(let machine) = row, let helper = crew.helper(id: machine.id) {
            Button("Rename…") { editing = .rename(helper) }
            Button("Edit brief…") { editing = .brief(helper) }
            Button(helper.isPaused ? "Resume" : "Pause") { crew.setPaused(helper, !helper.isPaused) }
            if catalog.isShared(helper) {
                Button("Stop sharing") { catalog.unshare(helper) }
            } else {
                Button("Share with team") { catalog.share(helper) }.disabled(catalog.folder == nil)
            }
            if catalog.isShared(helper, in: .everyone) {
                Button("Unpublish") { catalog.unshare(helper, from: .everyone) }
            } else {
                Button("Publish to the public catalog") { catalog.share(helper, to: .everyone) }
                    .disabled(catalog.publicFolder == nil)
            }
            Divider()
            Button("Delete…", role: .destructive) { deleting = helper }
        }
    }
}

/// The small dot beside a machine: blue while it reads, orange when it needs you, grey when it is idle.
private struct StatusDot: View {
    let status: MachineStatus
    @Environment(\.uiScale) private var scale

    var body: some View {
        Circle().fill(color).frame(width: 8 * scale, height: 8 * scale)
    }

    private var color: Color {
        switch status {
        case .reading: .accentFill
        case .needsYou: Tone.attention.color
        case .idle: .iconTint
        }
    }
}

/// What the machine sheet is for: a new machine, a new name, or a new brief.
enum MachineEdit: Identifiable {
    case new
    case rename(HelperModel)
    case brief(HelperModel)

    var id: String {
        switch self {
        case .new: "new"
        case .rename(let helper): "rename-\(helper.machine.id)"
        case .brief(let helper): "brief-\(helper.machine.id)"
        }
    }
}

private struct MachineSheet: View {
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
                Picker("Kind", selection: $template) {
                    ForEach(MachineTemplate.all) { Text($0.role).tag($0) }
                }
                .pickerStyle(.radioGroup)
                Text(template.detail).foregroundStyle(.supporting)
                if lacksFollowable { Text(Crew.nothingToFollow).foregroundStyle(Tone.bad.color) }
                TextField("Name", text: $text, prompt: Text(template.name)).textFieldStyle(.roundedBorder)
            case .rename:
                TextField("Name", text: $text).textFieldStyle(.roundedBorder)
                Text("A new name keeps its items, marks and trust.").foregroundStyle(.supporting)
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
                    "A new brief is a new version. Its marks and trust start again; the old version's stay in Settings › Advanced."
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
        .frame(width: 480)
        .onAppear(perform: fill)
    }

    /// A new machine that follows another has nothing to follow until a machine with a lifecycle (Pip) exists.
    private var lacksFollowable: Bool {
        guard case .new = edit else { return false }
        return template.spec.needsFollowed && crew.followable == nil
    }

    private var title: String {
        switch edit {
        case .new: "Add a machine"
        case .rename(let helper): "Rename \(helper.name)"
        case .brief(let helper): "\(helper.name)'s brief"
        }
    }

    private var saveTitle: String {
        switch edit {
        case .new: "Add"
        case .rename: "Rename"
        case .brief: "Save version"
        }
    }

    private func fill() {
        switch edit {
        case .new: text = ""
        case .rename(let helper): text = helper.name
        case .brief(let helper): text = helper.spec.brief
        }
    }

    private func save() {
        switch edit {
        case .new: done(crew.create(from: template, name: text))
        case .rename(let helper):
            crew.rename(helper, to: text)
            done(nil)
        case .brief(let helper):
            crew.edit(helper, brief: text)
            done(nil)
        }
        dismiss()
    }
}
