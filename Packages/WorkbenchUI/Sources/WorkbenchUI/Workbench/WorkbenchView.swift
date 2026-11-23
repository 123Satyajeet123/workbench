import SwiftUI
import WorkbenchCore

/// The main window: a sidebar and the open page in the system's split view, with the system's title bar, toolbar and
/// sidebar button, and the right panel as the system's inspector.
struct WorkbenchView: View {
    static let minimumSize = CGSize(width: 900, height: 600)
    static let idealSize = CGSize(width: 1160, height: 780)
    private static let sidebarWidths: ClosedRange<CGFloat> = 200...320

    @SceneStorage("selection") private var selection = SidebarSelection.day
    @State private var columns = NavigationSplitViewVisibility.all
    @State private var panel = PanelSwitch()
    @State private var shell: ShellState
    @Environment(Crew.self) private var crew
    @Environment(TodayModel.self) private var today
    @Environment(ReviewModel.self) private var review
    @Environment(TeamModel.self) private var team
    @Environment(CaptureSettings.self) private var capture
    @Environment(Navigation.self) private var navigation
    @Environment(\.openSettings) private var openSettings
    @Environment(\.uiScale) private var scale

    init(session: AppSession) {
        _shell = State(initialValue: ShellState(session: session))
    }

    private var sections: [SidebarSection] {
        let machines = crew.crew.map {
            SidebarMachine(
                id: $0.machine.id, name: $0.name,
                status: MachineStatus(isReading: $0.phase == .reading, needsYou: $0.question != nil || $0.problem != nil))
        }
        return SidebarPlan.sections(
            template: team.template, machines: machines, today: today.needs.count, checks: review.items.count)
    }

    private var page: SidebarSelection { SidebarPlan.landing(selection, in: sections) }

    private var panelContent: PanelContent {
        PanelContent.of(
            hasFact: shell.selection.inspected != nil, hasPlaybook: shell.playbook.hasContent, isOn: panel.isOn)
    }

    var body: some View {
        let sections = sections
        NavigationSplitView(columnVisibility: $columns) {
            Sidebar(sections: sections, selection: pageSelection(in: sections))
                .navigationSplitViewColumnWidth(
                    min: Self.sidebarWidths.lowerBound * scale, ideal: 240 * scale,
                    max: Self.sidebarWidths.upperBound * scale)
        } detail: {
            content
                .navigationTitle(title)
                .toolbar(removing: .title)
                .toolbar { toolbar }
                .inspector(isPresented: isPanelPresented) { PanelView(content: panelContent) }
        }
        .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
        .environment(shell.selection).environment(shell.playbook).environment(shell.toast).environment(shell.proof)
        .environment(\.factActing, shell.acting.acting(for: page))
        .environment(\.factSurface, Surface(page: page))
        .toastHost(shell.toast)
        .overlay { if navigation.isPaletteOpen { palette } }
        .onChange(of: navigation.requested, initial: true) { _, requested in
            guard let requested else { return }
            show(requested)
            navigation.requested = nil
        }
        .onChange(of: navigation.requestedFact, initial: true) { _, requested in
            guard let requested else { return }
            openFact(requested)
            navigation.requestedFact = nil
        }
        .onChange(of: shell.selection.inspected) { _, fact in if fact != nil { panel.isOn = true } }
    }

    private var title: String {
        if case .machine(let id) = page, let helper = crew.helper(id: id) { return helper.name }
        return page.title
    }

    private var content: some View {
        pageView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.pageFill)
    }

    @ViewBuilder private var pageView: some View {
        switch page {
        case .day: TodayPage()
        case .people: FactGroupsPage(lens: .people)
        case .projects: FactGroupsPage(lens: .projects)
        case .mochi: MochiPage(open: show)
        case .crew, .advanced: CrewPage(open: show)
        case .machine(let id): if let helper = crew.helper(id: id) { HelperPage(model: helper) }
        case .calls: CallsPage()
        case .review: ReviewPage()
        case .deals: DealsPage()
        case .catalog: TeamCatalogPage(open: show)
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Search", systemImage: "magnifyingglass") { navigation.isPaletteOpen = true }
                .help("Go to a page or find a fact (⌘K)")
            Button("Panel", systemImage: "sidebar.trailing", action: togglePanel)
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(panelContent == .hidden && !shell.playbook.hasContent)
                .help("Show or hide the panel (⌘⌥I)")
        }
    }

    private var palette: some View {
        let facts = ShellFacts.open(today: today, review: review)
        return ZStack(alignment: .top) {
            Color.black.opacity(0.18).onTapGesture { navigation.isPaletteOpen = false }
            PaletteView(
                commands: PaletteEntries.commands(
                    sections: sections, capture: capture.mode, isRecording: capture.call != nil),
                facts: PaletteEntries.facts(facts),
                callChoices: PaletteEntries.callChoices(apps: capture.playingApps.map { ($0.id, $0.name) }),
                run: run, close: { navigation.isPaletteOpen = false }
            )
            .padding(.top, 80)
        }
    }

    private func pageSelection(in sections: [SidebarSection]) -> Binding<SidebarSelection> {
        Binding(get: { SidebarPlan.landing(selection, in: sections) }, set: { selection = $0 })
    }

    private var isPanelPresented: Binding<Bool> {
        Binding(
            get: { panelContent != .hidden },
            set: { if !$0 { togglePanel() } })
    }

    private func togglePanel() {
        panel.toggle(hasFact: shell.selection.inspected != nil) { _ = shell.selection.closeInspector() }
    }

    /// Shows a page of the window. Advanced is in Settings, so it opens there and the window stays where it is.
    private func show(_ page: SidebarSelection) {
        guard page == .advanced else {
            selection = SidebarPlan.landing(page, in: sections)
            return
        }
        navigation.settingsTab = .advanced
        openSettings()
    }

    private func openFact(_ id: Int64) {
        today.refresh()
        let facts = ShellFacts.open(today: today, review: review)
        guard let item = ShellFacts.item(id, in: facts) else { return }
        shell.selection.select(item)
        shell.selection.inspected = item
    }

    private func run(_ action: PaletteEntry.Action) {
        switch action {
        case .go(let page): show(page)
        case .pauseCapture: capture.mode = .paused
        case .resumeCapture: capture.mode = .on
        case .privateMode(let isOn): capture.mode = isOn ? .privateHour : .on
        case .stopCall: capture.stopCall()
        case .startCall(let appID):
            capture.startCall(
                in: capture.playingApps.first { $0.id == appID }, confirmed: capture.mode == .privateHour)
        case .settings: openSettings()
        case .openFact(let id): navigation.show(fact: id)
        case .chooseCall: break
        }
    }
}
