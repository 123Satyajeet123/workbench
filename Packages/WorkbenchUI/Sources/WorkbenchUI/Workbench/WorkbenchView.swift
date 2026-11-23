import SwiftUI

struct WorkbenchView: View {
    static let minimumSize = CGSize(width: 900, height: 600)
    static let idealSize = CGSize(width: 1160, height: 780)
    static let sidebarWidth: CGFloat = 240
    static let railWidth: CGFloat = 56

    @SceneStorage("tabs") private var savedTabs = ""
    @SceneStorage("sidebarShown") private var isSidebarShown = true
    @State private var buttons = WindowButtons.compact
    @State private var tabs = PageTabs()
    @State private var isSearching = false
    @Environment(Crew.self) private var crew
    @Environment(TodayModel.self) private var today
    @Environment(Navigation.self) private var navigation
    @Environment(CaptureSettings.self) private var capture
    @Environment(\.uiScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let titleBar = buttons.center * 2
        HStack(spacing: 0) {
            Sidebar(
                selection: Binding(get: { tabs.page }, set: { tabs.open($0) }), titleBar: titleBar,
                toggleLeading: toggleLeading, isRail: !isSidebarShown,
                toggle: toggleSidebar, openInNewTab: { tabs.openNewTab($0) }
            )
            .frame(width: (isSidebarShown ? Self.sidebarWidth : Self.railWidth) * scale)
            .zIndex(1)
            Rectangle().fill(.dividerLine).frame(width: 1).padding(.top, isSidebarShown ? 0 : titleBar)
                .background(isSidebarShown ? Color.clear : .sidebarFill)
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, titleBar)
                .background(.pageFill)
                .overlay(alignment: .top) { topRow(height: titleBar) }
        }
        .ignoresSafeArea(edges: .top)
        .blur(radius: isSearching ? 10 : 0)
        .overlay(alignment: .top) { if isSearching { search.transition(.opacity.combined(with: .scale(0.97))) } }
        .animation(Motion.settle(reduceMotion: reduceMotion), value: isSearching)
        .background(WindowChrome { measured in buttons = measured })
        .frame(
            minWidth: Self.minimumSize.width, idealWidth: Self.idealSize.width, minHeight: Self.minimumSize.height,
            idealHeight: Self.idealSize.height
        )
        .onAppear { tabs = PageTabs(saved: savedTabs, isOpen: isRestorable) }
        .onChange(of: tabs) { savedTabs = tabs.saved }
        .onChange(of: navigation.requested, initial: true) { _, page in
            guard let page else { return }
            show(page)
            navigation.requested = nil
        }
    }

    @ViewBuilder private var page: some View {
        switch tabs.page {
        case .day: TodayPage()
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
        }
    }

    private var toggleLeading: CGFloat { buttons.trailing + Space.xs }

    private func topRow(height: CGFloat) -> some View {
        HStack(spacing: 0) {
            if !isSidebarShown {
                SidebarToggle(isShown: false, toggle: toggleSidebar)
                    .padding(.leading, max(Space.xs, toggleLeading - Self.railWidth * scale - 1))
            }
            HStack(spacing: Space.xs) {
                Button("Back", systemImage: "chevron.left") { tabs.goBack(isOpen: isOpen) }
                    .keyboardShortcut("[", modifiers: .command).disabled(!tabs.canGoBack).help("Back (⌘[)")
                Button("Forward", systemImage: "chevron.right") { tabs.goForward(isOpen: isOpen) }
                    .keyboardShortcut("]", modifiers: .command).disabled(!tabs.canGoForward).help("Forward (⌘])")
            }
            .padding(.horizontal, Space.m)
            TabStrip(tabs: $tabs, height: height)
            Color.clear.frame(minWidth: Space.l, maxWidth: .infinity).contentShape(.rect)
                .gesture(WindowDragGesture())
            Button("Search", systemImage: "magnifyingglass") { isSearching = true }.help("Search (⌘K)")
                .padding(.trailing, Space.m)
        }
        .background { tabShortcuts }
        .labelStyle(.iconOnly).buttonStyle(.ghost).foregroundStyle(.sidebarIcon)
        .frame(height: height)
        .background(alignment: .bottom) { Rectangle().fill(.dividerLine).frame(height: 1) }
        .background(.sidebarFill)
    }

    private func toggleSidebar() {
        withAnimation(Motion.settle(reduceMotion: reduceMotion)) { isSidebarShown.toggle() }
    }

    private var tabShortcuts: some View {
        Group {
            Button("Search") { isSearching.toggle() }.keyboardShortcut("k", modifiers: .command)
            Button("New tab") { tabs.openNewTab() }.keyboardShortcut("t", modifiers: .command)
            Button("Close tab") { tabs.close(tabs.selected) }.keyboardShortcut("w", modifiers: .command)
                .disabled(!tabs.canClose)
            Button("Next tab") { tabs.selectNext() }.keyboardShortcut(.tab, modifiers: .control)
            Button("Previous tab") { tabs.selectPrevious() }.keyboardShortcut(.tab, modifiers: [.control, .shift])
        }
        .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
    }

    private var search: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.3).ignoresSafeArea().onTapGesture { isSearching = false }
            QuickOpenPanel(
                entries: QuickOpen.entries(
                    pages: SidebarLayout.pages + [.usage, .settings],
                    machines: crew.crew.map { ($0.machine.id, $0.name) },
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
            .padding(.top, 96)
        }
    }

    private func show(_ page: SidebarSelection) { tabs.open(page) }

    private func isOpen(_ page: SidebarSelection) -> Bool {
        if case .machine(let id) = page { return crew.helper(id: id) != nil }
        return true
    }

    private func isRestorable(_ page: SidebarSelection) -> Bool { isOpen(page) && SidebarLayout.lists(page) }
}

struct TabStrip: View {
    @Binding var tabs: PageTabs
    let height: CGFloat
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
                .font(.system(size: 15)).frame(width: height, height: height).help("New tab (⌘T)")
            line
        }
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
        PageCrumb(page: page, isSelected: isSelected)
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

private struct PageCrumb: View {
    let page: SidebarSelection
    var isSelected = true
    @Environment(Crew.self) private var crew

    var body: some View {
        HStack(spacing: Space.s) {
            icon.frame(width: 18, height: 18)
            Text(title).textStyle(.body).lineLimit(1)
                .foregroundStyle(isSelected ? Color.bodyText : .sidebarText)
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        if case .machine(let id) = page { return crew.helper(id: id)?.name ?? page.title }
        return page.title
    }

    @ViewBuilder private var icon: some View {
        if case .machine(let id) = page, let helper = crew.helper(id: id) {
            Mascot(look: .of(helper.machine), size: 18)
        } else if let look = page.look {
            Mascot(look: look, size: 18)
        } else {
            Image(systemName: SidebarLayout.symbol(of: page) ?? "doc").font(.system(size: 15))
                .foregroundStyle(.sidebarIcon)
        }
    }
}
