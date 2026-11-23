import AppKit
import SwiftUI
import WorkbenchCore

enum SidebarLayout {
    enum Entry: Equatable {
        case page(SidebarSelection, symbol: String)
        case helper(SidebarSelection)
    }

    struct Section: Equatable {
        var title: String?
        var entries: [Entry]
    }

    static let sections = [
        Section(entries: [
            .page(.day, symbol: "sun.max"), .page(.people, symbol: "person.2"),
            .page(.projects, symbol: "square.stack.3d.up"), .helper(.calls),
            .page(.deals, symbol: "rectangle.3.group"),
        ]),
        Section(
            title: "Crew",
            entries: [
                .helper(.mochi), .page(.crew, symbol: "rectangle.grid.2x2"),
                .page(.review, symbol: "checkmark.circle"), .page(.catalog, symbol: "person.crop.rectangle.stack"),
            ]),
    ]

    static var pages: [SidebarSelection] {
        sections.flatMap(\.entries).map { entry in
            switch entry {
            case .page(let page, _), .helper(let page): page
            }
        }
    }

    static func symbol(of page: SidebarSelection) -> String? {
        if page == .usage { return "chart.xyaxis.line" }
        if page == .settings { return "gearshape" }
        for case .page(let listed, let symbol) in sections.flatMap(\.entries) where listed == page { return symbol }
        return nil
    }
}

/// The fixed pages, the person's favourite and recent pages, and the tree of the workspace, in one native sidebar
/// list. Usage and Settings stay at the foot.
struct Sidebar: View {
    @Binding var selection: SidebarSelection
    var openInNewTab: (SidebarSelection) -> Void = { _ in }
    @Environment(IdentityModel.self) private var identity
    @Environment(TeamModel.self) private var team
    @Environment(Crew.self) private var crew
    @Environment(ReviewModel.self) private var review
    @Environment(TodayModel.self) private var today
    @Environment(TeamCatalogModel.self) private var catalog
    @Environment(DealsModel.self) private var deals
    @Environment(WorkspaceModel.self) private var workspace
    @Environment(PlanUsage.self) private var planUsage
    @Environment(ModelSettings.self) private var models
    @State private var editing: MachineEdit?
    @State private var deleting: HelperModel?
    @State private var renaming: WorkObjectID?
    @SceneStorage("recentsShown") private var recentsShown = false

    var body: some View {
        List(selection: listSelection) {
            ForEach(SidebarLayout.sections.indices, id: \.self) { index in section(SidebarLayout.sections[index]) }
            if !workspace.favorites.isEmpty {
                Section("Favorites") { ForEach(workspace.favorites) { PageLabel(page: $0).tag($0) } }
            }
            if !workspace.recents.isEmpty {
                Section("Recents", isExpanded: $recentsShown) {
                    ForEach(workspace.recents) { PageLabel(page: $0).tag($0) }
                }
            }
            Section {
                ForEach(workspace.roots) { TreeNode(object: $0, renaming: $renaming, rename: rename) }
                    .dropDestination(for: String.self) { ids, index in workspace.drop(ids, into: nil, at: index) }
            } header: {
                workspaceHeader
            }
        }
        .listStyle(.sidebar)
        .contextMenu(forSelectionType: SidebarSelection.self) { pages in menu(for: pages) }
        .onKeyPress(.return) { startRenaming(selection) ? .handled : .ignored }
        .onDeleteCommand { archive(selection) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                usageRow
                settingsRow
            }
        }
        .onChange(of: crew.crew.map(\.machine.id)) { workspace.refresh() }
        .onChange(of: deals.deals.map(\.id)) { workspace.refresh() }
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

    private func section(_ section: SidebarLayout.Section) -> some View {
        Section {
            ForEach(section.entries.indices, id: \.self) { index in entry(section.entries[index]) }
        } header: {
            if let title = section.title {
                HStack {
                    Text(title)
                    Spacer()
                    Button("Add a machine", systemImage: "plus") { editing = .new }
                        .labelStyle(.iconOnly).buttonStyle(.borderless).help("Add a machine")
                }
            }
        }
    }

    @ViewBuilder private func entry(_ entry: SidebarLayout.Entry) -> some View {
        switch entry {
        case .page(let page, let symbol):
            Label(page.title, systemImage: symbol).badge(count(of: page)).help(page.role).tag(page)
        case .helper(let page):
            Label {
                Text(page.title)
            } icon: {
                page.look.map { Mascot(look: $0, size: 18, mood: page == .mochi ? mochiMood : .calm) }
            }
            .help(page.role).tag(page)
        }
    }

    private var workspaceHeader: some View {
        HStack {
            Text(team.team.name.cleaned ?? "Workspace")
            Spacer()
            Menu("New", systemImage: "plus") { newItems(under: nil) }
                .labelStyle(.iconOnly).menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("New folder or page")
        }
    }

    private func count(of page: SidebarSelection) -> Int {
        switch page {
        case .day: today.needsCount
        case .review: review.items.count
        case .catalog: catalog.teammates.count + catalog.teammatesDays.count
        default: 0
        }
    }

    @ViewBuilder private func menu(for pages: Set<SidebarSelection>) -> some View {
        if let page = pages.first, pages.count == 1 {
            Button("Open in new tab") { openInNewTab(page) }
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

    private var planWindow: PlanLimits.Window? {
        guard models.billing == .plan, let limits = planUsage.limits else { return nil }
        return limits.fiveHour ?? limits.week
    }

    private var usageRow: some View {
        footRow(.usage, help: usageSummary) {
            PlanRing(window: planWindow, size: 18)
            Text(SidebarSelection.usage.title).lineLimit(1)
            Spacer()
            if let planWindow {
                Text(PlanRing.percent(planWindow.used)).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }

    private var usageSummary: String {
        guard models.billing == .plan, let limits = planUsage.limits else { return SidebarSelection.usage.title }
        return "Claude plan\n" + limits.summary
    }

    private var settingsRow: some View {
        footRow(.settings, help: "Settings (⌘,)") {
            Monogram(name: identity.identity.hasName ? identity.identity.name : "You", size: 20)
            Text(identity.identity.hasName ? identity.identity.name : "You").lineLimit(1)
            Spacer()
            Image(systemName: "gearshape").foregroundStyle(.secondary)
        }
    }

    private func footRow(_ page: SidebarSelection, help: String, @ViewBuilder label: () -> some View) -> some View {
        Button {
            listSelection.wrappedValue = page
        } label: {
            HStack(spacing: Space.s) { label() }
                .padding(.horizontal, Space.s).padding(.vertical, Space.xs + 2)
                .background(selection == page ? Color.selectedFill : .clear, in: .rect(cornerRadius: Radius.control))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Space.s).padding(.vertical, 1)
        .help(help)
        .contextMenu { Button("Open in new tab") { openInNewTab(page) } }
        .accessibilityAddTraits(selection == page ? .isSelected : [])
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
                HStack {
                    Text(object.name)
                    if let helper, helper.mood != .calm {
                        Spacer()
                        Circle().fill(dot(helper.mood)).frame(width: 7, height: 7)
                            .accessibilityLabel(status(helper.mood))
                    }
                }
            }
        } icon: {
            Image(systemName: helper?.machine.symbol ?? object.symbol)
                .opacity(helper?.isPaused == true ? 0.5 : 1)
        }
        .help(helper?.role ?? object.type.noun.capitalized)
    }

    private func dot(_ mood: Mascot.Mood) -> Color {
        switch mood {
        case .working: .accentColor
        case .trouble: Tone.bad.color
        default: Tone.attention.color
        }
    }

    private func status(_ mood: Mascot.Mood) -> String {
        switch mood {
        case .working: "Reading"
        case .trouble: "Has a problem"
        default: "Needs you"
        }
    }
}
