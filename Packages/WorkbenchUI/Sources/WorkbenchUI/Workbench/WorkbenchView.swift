import SwiftUI

struct WorkbenchView: View {
    static let minimumSize = CGSize(width: 900, height: 600)
    static let idealSize = CGSize(width: 1160, height: 780)
    static let sidebarWidth: CGFloat = 240

    @SceneStorage("selection") private var selection = SidebarSelection.day
    @SceneStorage("sidebarShown") private var isSidebarShown = true
    @State private var buttons = WindowButtons.unified
    @Environment(Crew.self) private var crew
    @Environment(Navigation.self) private var navigation
    @Environment(\.openSettings) private var openSettings
    @Environment(\.uiScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let titleBar = buttons.center * 2
        HStack(spacing: 0) {
            if isSidebarShown {
                Sidebar(
                    selection: $selection, titleBar: titleBar, toggleLeading: toggleLeading, hide: toggleSidebar
                )
                .frame(width: Self.sidebarWidth * scale)
                .transition(.move(edge: .leading))
                Rectangle().fill(.dividerLine).frame(width: 1)
            }
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, titleBar)
                .background(.pageFill)
                .overlay(alignment: .top) { topRow(height: titleBar) }
        }
        .ignoresSafeArea(edges: .top)
        .background(WindowChrome { measured in buttons = measured })
        .frame(
            minWidth: Self.minimumSize.width, idealWidth: Self.idealSize.width, minHeight: Self.minimumSize.height,
            idealHeight: Self.idealSize.height
        )
        .onAppear { if !SidebarLayout.lists(selection) { selection = .day } }
        .onChange(of: navigation.requested, initial: true) { _, page in
            guard let page else { return }
            show(page)
            navigation.requested = nil
        }
    }

    @ViewBuilder private var page: some View {
        switch selection {
        case .day: TodayPage()
        case .people: FactGroupsPage(lens: .people)
        case .projects: FactGroupsPage(lens: .projects)
        case .mochi: MochiPage(open: show)
        case .crew, .advanced: CrewPage(open: show)
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
        }
    }

    private var toggleLeading: CGFloat { buttons.trailing + Space.xs }

    private func topRow(height: CGFloat) -> some View {
        HStack(spacing: 0) {
            if !isSidebarShown {
                SidebarToggle(isShown: false, toggle: toggleSidebar).padding(.leading, toggleLeading)
            }
            Spacer()
        }
        .frame(height: height)
        .contentShape(.rect)
        .gesture(WindowDragGesture())
    }

    private func toggleSidebar() {
        withAnimation(Motion.settle(reduceMotion: reduceMotion)) { isSidebarShown.toggle() }
    }

    private func show(_ page: SidebarSelection) {
        guard page == .advanced else {
            selection = page
            return
        }
        navigation.settingsTab = .advanced
        openSettings()
    }
}
