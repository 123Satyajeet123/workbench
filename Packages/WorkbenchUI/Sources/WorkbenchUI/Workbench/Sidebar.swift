import SwiftUI
import WorkbenchCore

struct Sidebar: View {
    @Binding var selection: SidebarSelection
    @Environment(IdentityModel.self) private var identity
    @Environment(Crew.self) private var crew
    @Environment(ReviewModel.self) private var review
    @Environment(TeamCatalogModel.self) private var catalog
    @State private var editing: MachineEdit?
    @State private var deleting: HelperModel?

    var body: some View {
        List(selection: Binding<SidebarSelection?>(get: { selection }, set: { if let new = $0 { selection = new } })) {
            FixedRow(page: .day, faceSize: 34, mood: mochiMood).tag(SidebarSelection.day)
            Label(SidebarSelection.review.title, systemImage: "checkmark.circle")
                .badge(review.items.count)
                .tag(SidebarSelection.review)
            Section {
                ForEach(crew.crew, id: \.machine.id) { helper in
                    MachineRow(helper: helper)
                        .tag(SidebarSelection.machine(helper.machine.id))
                        .contextMenu { menu(for: helper) }
                }
                FixedRow(page: .calls, faceSize: 26, mood: .calm).tag(SidebarSelection.calls)
            } header: {
                HStack {
                    Text("Crew")
                    Spacer()
                    Button("Add a machine", systemImage: "plus") { editing = .new }
                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                }
            }
            Section("Team") {
                Label(SidebarSelection.deals.title, systemImage: "rectangle.3.group").tag(SidebarSelection.deals)
                Label(SidebarSelection.catalog.title, systemImage: "person.3.sequence")
                    .badge(catalog.teammates.count + catalog.teammatesDays.count)
                    .tag(SidebarSelection.catalog)
            }
            Section("Meter") {
                Label(SidebarSelection.runs.title, systemImage: "gauge.with.dots.needle.33percent")
                    .tag(SidebarSelection.runs)
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
        .safeAreaInset(edge: .bottom) { settingsRow }
        .sheet(item: $editing) { edit in
            MachineSheet(edit: edit) { id in if let id { selection = .machine(id) } }
        }
        .confirmationDialog(
            "Delete \(deleting?.name ?? "")?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { helper in
            Button("Delete \(helper.name)", role: .destructive) {
                if selection == .machine(helper.machine.id) { selection = .day }
                crew.delete(helper)
            }
        } message: { helper in
            Text(
                "Its \(helper.spec.itemsNoun), your marks on them and its settings are deleted. Its runs stay on Runs.")
        }
    }

    @ViewBuilder private func menu(for helper: HelperModel) -> some View {
        Button("Rename…") { editing = .rename(helper) }
        Button("Edit brief…") { editing = .brief(helper) }
        Button(helper.isPaused ? "Resume" : "Pause") { crew.setPaused(helper, !helper.isPaused) }
        if catalog.isShared(helper) {
            Button("Stop sharing") { catalog.unshare(helper) }
        } else {
            Button("Share with team") { catalog.share(helper) }.disabled(catalog.folder == nil)
        }
        Divider()
        Button("Delete…", role: .destructive) { deleting = helper }
    }

    private var settingsRow: some View {
        SettingsLink {
            HStack(spacing: Space.s) {
                Monogram(name: identity.identity.hasName ? identity.identity.name : "You")
                Text(identity.identity.hasName ? identity.identity.name : "You").lineLimit(1)
                Spacer()
                Image(systemName: "gearshape").foregroundStyle(.supporting)
            }
            .padding(Space.m)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Settings (⌘,)")
    }

    /// Mochi shows the most urgent mood of the crew.
    private var mochiMood: Mascot.Mood {
        let moods = crew.machines.map(\.mood)
        return [.working, .trouble, .asking].first(where: moods.contains) ?? .calm
    }
}

private struct FixedRow: View {
    let page: SidebarSelection
    let faceSize: CGFloat
    let mood: Mascot.Mood

    var body: some View {
        HStack(spacing: Space.s) {
            if let look = page.look { Mascot(look: look, size: faceSize, mood: mood) }
            VStack(alignment: .leading, spacing: 0) {
                Text(page.title).fontWeight(.medium)
                Text(page.role).textStyle(.caption).foregroundStyle(.supporting)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct MachineRow: View {
    let helper: HelperModel

    var body: some View {
        HStack(spacing: Space.s) {
            Mascot(look: .of(helper.machine), size: 26, mood: helper.mood)
            VStack(alignment: .leading, spacing: 0) {
                Text(helper.name).fontWeight(.medium)
                Text(helper.isPaused ? "Paused" : MachineTemplate.of(helper.machine)?.role ?? "")
                    .textStyle(.caption).foregroundStyle(.supporting)
            }
        }
        .opacity(helper.isPaused ? 0.6 : 1)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
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
                    "Reads up to \(HelperModel.trialDays) recent days with the new brief beside the current one. Nothing changes until you switch."
                )
                Text("A new brief is a new version. Its marks and trust start again; the old version's stay on Runs.")
                    .foregroundStyle(.supporting)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(action: save) { Text(saveTitle) }.buttonStyle(.borderedProminent).keyboardShortcut(
                    .defaultAction)
            }
        }
        .padding(Space.l)
        .frame(width: 480)
        .onAppear(perform: fill)
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
