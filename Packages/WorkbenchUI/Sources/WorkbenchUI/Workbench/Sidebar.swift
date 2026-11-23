import AppKit
import SwiftUI
import WorkbenchCore

/// The fixed top (Mochi, Search, Recents, Favorites), the workspace and its tree, the Private section, and Sources and
/// Settings at the foot, in one native sidebar list. Everything in the tree is the person's to make, rename, nest,
/// move and archive.
struct Sidebar: View {
    @Binding var selection: SidebarSelection
    var openInNewTab: (SidebarSelection) -> Void = { _ in }
    var search: () -> Void = {}
    @Environment(TeamModel.self) private var team
    @Environment(CaptureSettings.self) private var capture
    @Environment(Navigation.self) private var navigation
    @Environment(Crew.self) private var crew
    @Environment(TodayModel.self) private var today
    @Environment(TeamCatalogModel.self) private var catalog
    @Environment(DealsModel.self) private var deals
    @Environment(WorkspaceModel.self) private var workspace
    @State private var editing: MachineEdit?
    @State private var deleting: HelperModel?
    @State private var renaming: WorkObjectID?
    @SceneStorage("recentsShown") private var recentsShown = false

    var body: some View {
        List(selection: listSelection) {
            Section {
                mochiRow
                Button(action: search) { Label("Search", systemImage: "magnifyingglass").sidebarRowFont() }
                    .buttonStyle(.plain).help("Search (⌘K)")
            }
            if !workspace.recents.isEmpty {
                Section("Recents", isExpanded: $recentsShown) {
                    ForEach(workspace.recents) { PageLabel(page: $0).sidebarRowFont().tag($0) }
                }
            }
            if !workspace.favorites.isEmpty {
                Section("Favorites") { ForEach(workspace.favorites) { PageLabel(page: $0).sidebarRowFont().tag($0) } }
            }
            Section {
                tree(workspace.roots, under: nil)
            } header: {
                workspaceMenu
            }
            Section {
                tree(workspace.privateItems, under: workspace.privateSection)
            } header: {
                HStack {
                    Text("Private").help("Yours. Who can read a page follows its sources, not its folder.")
                    Spacer()
                    Menu("New", systemImage: "plus") { newItems(under: workspace.privateSection) }
                        .labelStyle(.iconOnly).menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .help("New folder or page in Private")
                }
            }
        }
        .listStyle(.sidebar)
        .contextMenu(forSelectionType: SidebarSelection.self) { pages in menu(for: pages) }
        .onKeyPress(.return) { startRenaming(selection) ? .handled : .ignored }
        .onDeleteCommand { archive(selection) }
        .safeAreaInset(edge: .bottom, spacing: 0) { foot }
        .onChange(of: crew.crew.map(\.machine.id)) { workspace.refresh() }
        .onChange(of: deals.deals.map(\.id)) { workspace.refresh() }
        .sheet(item: $editing) { edit in
            MachineSheet(edit: edit) { id in
                workspace.refresh()
                if let id { selection = .machine(id) }
            }
        }
        .confirmationDialog(
            "Delete \(deleting?.name ?? "")?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { helper in
            Button("Delete \(helper.name)", role: .destructive) {
                if selection == .machine(helper.machine.id) { selection = .day }
                crew.delete(helper)
                workspace.refresh()
            }
        } message: { helper in
            Text(
                "Its \(helper.spec.itemsNoun), your marks on them and its settings are deleted. Its calls stay on the Usage page."
            )
        }
    }

    /// A click opens the page; a ⌘-click opens it in a new tab.
    private var listSelection: Binding<SidebarSelection?> {
        Binding(
            get: { selection },
            set: { page in
                guard let page else { return }
                if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
                    openInNewTab(page)
                } else {
                    selection = page
                }
            })
    }

    /// Mochi is the home: its row opens Today, with the count of what needs you.
    private var mochiRow: some View {
        Label {
            Text(SidebarSelection.mochi.title)
        } icon: {
            Mascot(look: .mochi, size: SidebarRowFont.iconSize, mood: mochiMood)
        }
        .sidebarRowFont()
        .badge(today.needsCount)
        .help(SidebarSelection.day.role)
        .tag(SidebarSelection.day)
    }

    /// The rows of one level of the tree. A row dragged between them takes that place under `parent`.
    private func tree(_ objects: [WorkObject], under parent: WorkObjectID?) -> some View {
        ForEach(objects) { TreeNode(object: $0, renaming: $renaming, rename: rename) }
            .dropDestination(for: String.self) { ids, index in workspace.drop(ids, into: parent, at: index) }
    }

    /// The workspace: its name, and the menu that switches to the other profile's data and makes new items.
    private var workspaceMenu: some View {
        Menu {
            if let other = ProfileSwitch.available(from: capture.profile) {
                Button(ProfileSwitch.title(to: other)) { ProfileSwitch.go(to: other) }
                Divider()
            }
            newItems(under: nil)
        } label: {
            HStack(spacing: Space.xs) {
                Text(team.team.name.cleaned ?? "Workspace")
                Image(systemName: "chevron.down").imageScale(.small)
            }
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Your workspace")
    }

    private var foot: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if let problem = workspace.problems.text {
                Text(problem).textStyle(.callout).foregroundStyle(Tone.bad.color)
            }
            if let notice = workspace.notice {
                HStack(alignment: .firstTextBaseline) {
                    Text(notice).textStyle(.callout).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("Dismiss", systemImage: "xmark") { workspace.notice = nil }
                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                }
            }
            HStack {
                Button("Sources", systemImage: "arrow.left.arrow.right") { navigation.openSettings(.capture) }
                    .help("What Workbench reads")
                Spacer()
                Button("Settings", systemImage: "gearshape") { selection = .settings }.help("Settings (⌘,)")
            }
            .buttonStyle(.borderless)
            .sidebarRowFont()
        }
        .padding(.horizontal, Space.m).padding(.vertical, Space.s)
    }

    @ViewBuilder private func menu(for pages: Set<SidebarSelection>) -> some View {
        if let page = pages.first, pages.count == 1 {
            Button("Open in new tab") { openInNewTab(page) }
            if page == .day { Button("Open Mochi's page") { selection = .mochi } }
            Button(workspace.isFavorite(page) ? "Remove from Favorites" : "Add to Favorites") {
                workspace.toggleFavorite(page)
            }
            if let object = crew.object(of: page, in: workspace) {
                Divider()
                newItems(under: object.id)
                Button("Rename") { renaming = object.id }
                if let helper = crew.helper(page: object.id) {
                    machineItems(for: helper)
                } else {
                    Divider()
                    Button("Archive") { archive(page) }
                }
            }
        } else if pages.isEmpty {
            newItems(under: nil)
        }
    }

    @ViewBuilder private func newItems(under parent: WorkObjectID?) -> some View {
        Button("New folder") { make(ObjectTypes.folder, "New folder", under: parent) }
        Button("New page") { make(ObjectTypes.page, "Untitled", under: parent) }
        Button("New machine…") { editing = .new(in: parent) }
    }

    @ViewBuilder private func machineItems(for helper: HelperModel) -> some View {
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

    private func make(_ type: ObjectType, _ name: String, under parent: WorkObjectID?) {
        guard let made = workspace.create(type, under: parent, name: name) else { return }
        selection = .page(made.id)
        renaming = made.id
    }

    /// A machine's page takes the machine's name, so renaming it renames the machine.
    private func rename(_ object: WorkObject, to name: String) {
        renaming = nil
        guard name.cleaned != nil, name != object.name else { return }
        if let helper = crew.helper(page: object.id) {
            crew.rename(helper, to: name)
            workspace.refresh()
        } else {
            workspace.rename(object.id, to: name)
        }
    }

    private func startRenaming(_ page: SidebarSelection) -> Bool {
        guard renaming == nil, let object = crew.object(of: page, in: workspace) else { return false }
        renaming = object.id
        return true
    }

    /// Archives the object a page shows. A machine's page is not archived: the machine is deleted instead.
    private func archive(_ page: SidebarSelection) {
        guard let object = crew.object(of: page, in: workspace), crew.helper(page: object.id) == nil else { return }
        if selection == page { selection = .day }
        workspace.archive(object.id)
    }

    private var mochiMood: Mascot.Mood {
        let moods = crew.machines.map(\.mood)
        return [.working, .trouble, .asking].first(where: moods.contains) ?? .calm
    }
}

/// One row of the tree and, when it is open, the rows below it. A level loads when its row opens. A row drags to
/// another row to move under it, or between rows to take that place.
private struct TreeNode: View {
    let object: WorkObject
    @Binding var renaming: WorkObjectID?
    let rename: (WorkObject, String) -> Void
    @Environment(WorkspaceModel.self) private var workspace
    @Environment(Crew.self) private var crew

    var body: some View {
        if workspace.hasChildren(object.id) {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { workspace.isExpanded(object.id) }, set: { workspace.setExpanded(object.id, $0) })
            ) {
                ForEach(workspace.children(of: object.id)) { TreeNode(object: $0, renaming: $renaming, rename: rename) }
                    .dropDestination(for: String.self) { ids, index in
                        workspace.drop(ids, into: object.id, at: index)
                    }
            } label: {
                row
            }
        } else {
            row
        }
    }

    private var row: some View {
        TreeRow(object: object, helper: crew.helper(page: object.id), renaming: $renaming, rename: rename)
            .tag(crew.page(of: object))
            .draggable(object.id)
            .dropDestination(for: String.self) { ids, _ in
                let moved = ids.filter { $0 != object.id }
                workspace.drop(moved, into: object.id)
                return !moved.isEmpty
            }
    }
}

private struct TreeRow: View {
    let object: WorkObject
    let helper: HelperModel?
    @Binding var renaming: WorkObjectID?
    let rename: (WorkObject, String) -> Void
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        Label {
            if renaming == object.id {
                TextField("Name", text: $draft)
                    .focused($isFocused)
                    .onAppear {
                        draft = object.name
                        isFocused = true
                    }
                    .onSubmit { rename(object, draft) }
                    .onExitCommand { renaming = nil }
                    .onChange(of: isFocused) { _, focused in if !focused { rename(object, draft) } }
            } else {
                Text(object.name)
            }
        } icon: {
            if let helper {
                Mascot(look: .of(helper.machine), size: SidebarRowFont.iconSize, mood: helper.mood)
                    .opacity(helper.isPaused ? 0.5 : 1)
            } else {
                Image(systemName: object.symbol)
            }
        }
        .sidebarRowFont()
        .help(helper?.role ?? object.type.noun.capitalized)
    }
}

/// One text size for every row of the sidebar, the fixed ones at the foot too, at the window's zoom. The native list
/// sets its own size for its rows, so each row states this one.
enum SidebarRowFont {
    static let iconSize: CGFloat = 18
}

extension View {
    func sidebarRowFont() -> some View { textStyle(.body) }
}
