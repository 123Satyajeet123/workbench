import SwiftUI

struct WorkbenchView: View {
    static let minimumSize = CGSize(width: 680, height: 600)
    static let idealSize = CGSize(width: 1160, height: 780)

    @SceneStorage("tabs") private var savedTabs = ""
    @SceneStorage("sidebarShown") private var isSidebarShown = true
    @State private var tabs = PageTabs()
    @State private var isSearching = false
    @Environment(Crew.self) private var crew
    @Environment(WorkspaceModel.self) private var workspace
    @Environment(TodayModel.self) private var today
    @Environment(Navigation.self) private var navigation
    @Environment(CaptureSettings.self) private var capture
    @Environment(\.uiScale) private var scale

    var body: some View {
        NavigationSplitView(columnVisibility: columnVisibility) {
            Sidebar(
                selection: Binding(get: { tabs.page }, set: { tabs.open($0) }),
                openInNewTab: { tabs.openNewTab($0) },
                search: { isSearching = true }
            )
            .navigationSplitViewColumnWidth(min: 200 * scale, ideal: 240 * scale, max: 320 * scale)
        } detail: {
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.pageFill)
                .background { keyboardShortcuts }
                .toolbar { toolbar }
        }
        .sheet(isPresented: $isSearching) { search }
        .frame(
            minWidth: Self.minimumSize.width, idealWidth: Self.idealSize.width, minHeight: Self.minimumSize.height,
            idealHeight: Self.idealSize.height
        )
        .onAppear { tabs = PageTabs(saved: savedTabs, isOpen: isOpen) }
        .onChange(of: tabs) { savedTabs = tabs.saved }
        .onChange(of: tabs.page, initial: true) { _, page in workspace.visit(page) }
        .onChange(of: navigation.requested, initial: true) { _, page in
            guard let page else { return }
            show(page)
            navigation.requested = nil
        }
    }

    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(get: { isSidebarShown ? .all : .detailOnly }, set: { isSidebarShown = $0 != .detailOnly })
    }

    @ViewBuilder private var page: some View {
        switch tabs.page {
        case .day: TodayPage(open: show)
        case .people: FactGroupsPage(lens: .people)
        case .projects: FactGroupsPage(lens: .projects)
        case .mochi: MochiPage(open: show)
        case .crew: CrewPage(open: show)
        case .machine(let id):
            if let helper = crew.helper(id: id) {
                HelperPage(model: helper)
            } else {
                ContentUnavailableView("This machine was deleted", systemImage: "trash")
            }
        case .calls: CallsPage()
        case .review: ReviewPage()
        case .deals: DealsPage()
        case .catalog: TeamCatalogPage(open: show)
        case .usage: UsagePage()
        case .settings: SettingsPage()
        case .page(let id): WorkObjectPage(id: id, open: show, close: { tabs.goBack(isOpen: isOpen) })
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button("Back", systemImage: "chevron.left") { tabs.goBack(isOpen: isOpen) }
                .keyboardShortcut("[", modifiers: .command).disabled(!tabs.canGoBack).help("Back (⌘[)")
            Button("Forward", systemImage: "chevron.right") { tabs.goForward(isOpen: isOpen) }
                .keyboardShortcut("]", modifiers: .command).disabled(!tabs.canGoForward).help("Forward (⌘])")
        }
        ToolbarItem(placement: .navigation) { TabStrip(tabs: $tabs) }
        ToolbarItem(placement: .primaryAction) {
            Button("Search", systemImage: "magnifyingglass") { isSearching = true }.help("Search (⌘K)")
        }
    }

    private var keyboardShortcuts: some View {
        Group {
            Button("Search") { isSearching = true }.keyboardShortcut("k", modifiers: .command)
            Button("New tab") { tabs.openNewTab() }.keyboardShortcut("t", modifiers: .command)
            Button("Close tab") { tabs.close(tabs.selected) }.keyboardShortcut("w", modifiers: .command)
                .disabled(!tabs.canClose)
            Button("Next tab") { tabs.selectNext() }.keyboardShortcut(.tab, modifiers: .control)
            Button("Previous tab") { tabs.selectPrevious() }.keyboardShortcut(.tab, modifiers: [.control, .shift])
        }
        .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
    }

    private var search: some View {
        QuickOpenPanel(
            entries: QuickOpen.entries(
                pages: SidebarSelection.fixed,
                objects: workspace.everyObject().map { ($0.name, $0.noun, crew.page(of: $0)) },
                people: today.people.map(\.name), projects: today.projectGroups.map(\.name),
                settings: SettingsItem.all, switchTo: ProfileSwitch.available(from: capture.profile)),
            open: { entry, inNewTab in
                isSearching = false
                switch entry.target {
                case .page(let page, let section):
                    if let section { navigation.settingsSection = section }
                    if inNewTab { tabs.openNewTab(page) } else { tabs.open(page) }
                case .switchProfile(let profile):
                    ProfileSwitch.go(to: profile)
                }
            },
            close: { isSearching = false }
        )
    }

    private func show(_ page: SidebarSelection) { tabs.open(page) }

    private func isOpen(_ page: SidebarSelection) -> Bool {
        switch page {
        case .machine(let id): crew.helper(id: id) != nil
        case .page(let id): workspace.object(id) != nil
        default: true
        }
    }
}

struct TabStrip: View {
    static let height: CGFloat = 28

    @Binding var tabs: PageTabs
    @State private var dragged: PageTabs.Tab.ID?
    @State private var offset: CGFloat = 0
    @State private var tabWidth = TabChip.width.upperBound

    var body: some View {
        ViewThatFits(in: .horizontal) {
            strip
            ScrollView(.horizontal, showsIndicators: false) { strip }
        }
    }

    private var strip: some View {
        HStack(spacing: 0) {
            line
            ForEach(tabs.tabs) { tab in
                TabChip(
                    page: tab.page, isSelected: tab.id == tabs.selected, canClose: tabs.canClose,
                    select: { tabs.select(tab.id) }, close: { tabs.close(tab.id) },
                    drag: { distance in
                        dragged = tab.id
                        offset = distance
                    },
                    drop: { distance in
                        tabs.move(tab.id, by: Int((distance / max(tabWidth, 1)).rounded()))
                        dragged = nil
                        offset = 0
                    }
                )
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.width
                } action: {
                    tabWidth = $0
                }
                .offset(x: dragged == tab.id ? offset : 0)
                .zIndex(dragged == tab.id ? 1 : 0)
                .shadow(color: .black.opacity(dragged == tab.id ? 0.15 : 0), radius: 6)
                line
            }
            Button("New tab", systemImage: "plus") { tabs.openNewTab() }
                .labelStyle(.iconOnly).buttonStyle(.ghost).foregroundStyle(.sidebarIcon).font(.system(size: 15))
                .frame(width: Self.height, height: Self.height).help("New tab (⌘T)")
            line
        }
        .frame(height: Self.height)
    }

    private var line: some View { Rectangle().fill(.dividerLine).frame(width: 1) }
}

struct TabChip: View {
    static let width: ClosedRange<CGFloat> = 120...220

    let page: SidebarSelection
    let isSelected: Bool
    let canClose: Bool
    let select: () -> Void
    let close: () -> Void
    let drag: (CGFloat) -> Void
    let drop: (CGFloat) -> Void
    @State private var isHovered = false

    var body: some View {
        PageLabel(page: page).labelStyle(.titleAndIcon).textStyle(.body).lineLimit(1)
            .foregroundStyle(isSelected ? Color.bodyText : .sidebarText)
            .padding(.leading, Space.m).padding(.trailing, canClose ? Space.xl : Space.m)
            .frame(
                minWidth: Self.width.lowerBound, maxWidth: Self.width.upperBound, maxHeight: .infinity,
                alignment: .leading
            )
            .background(isSelected ? Color.pageFill : isHovered ? .hoverFill : .clear)
            .overlay { TabMouse(click: select, drag: drag, drop: drop) }
            .overlay(alignment: .trailing) {
                if canClose {
                    Button("Close tab", systemImage: "xmark", action: close).font(.system(size: 11, weight: .semibold))
                        .labelStyle(.iconOnly).buttonStyle(.ghost).foregroundStyle(.sidebarIcon)
                        .opacity(isHovered || isSelected ? 1 : 0).help("Close tab (⌘W)").padding(.trailing, Space.m)
                }
            }
            .contentShape(.rect)
            .onHover { isHovered = $0 }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            .accessibilityAction(named: "Open", select)
    }
}

private struct TabMouse: NSViewRepresentable {
    let click: () -> Void
    let drag: (CGFloat) -> Void
    let drop: (CGFloat) -> Void

    func makeNSView(context: Context) -> Tracker { Tracker() }

    func updateNSView(_ view: Tracker, context: Context) {
        view.click = click
        view.drag = drag
        view.drop = drop
    }

    final class Tracker: NSView {
        var click: () -> Void = {}
        var drag: (CGFloat) -> Void = { _ in }
        var drop: (CGFloat) -> Void = { _ in }
        private var start: CGFloat?
        private var isDragging = false

        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

        override func mouseDown(with event: NSEvent) {
            start = event.locationInWindow.x
            isDragging = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start else { return }
            let distance = event.locationInWindow.x - start
            if isDragging || abs(distance) > 4 {
                isDragging = true
                drag(distance)
            }
        }

        override func mouseUp(with event: NSEvent) {
            guard let start else { return }
            if isDragging { drop(event.locationInWindow.x - start) } else { click() }
            self.start = nil
            isDragging = false
        }
    }
}
