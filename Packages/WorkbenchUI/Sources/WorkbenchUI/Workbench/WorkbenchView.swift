import SwiftUI

struct WorkbenchView: View {
    static let minimumSize = CGSize(width: 900, height: 600)
    static let idealSize = CGSize(width: 1160, height: 780)

    @SceneStorage("selection") private var selection = SidebarSelection.day
    @Environment(Crew.self) private var crew
    @Environment(Navigation.self) private var navigation
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $selection)
        } detail: {
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
        .frame(
            minWidth: Self.minimumSize.width, idealWidth: Self.idealSize.width, minHeight: Self.minimumSize.height,
            idealHeight: Self.idealSize.height
        )
        .onChange(of: navigation.requested, initial: true) { _, page in
            guard let page else { return }
            show(page)
            navigation.requested = nil
        }
    }

    /// Shows a page of the window. Advanced is in Settings, so it opens there and the window stays where it is.
    private func show(_ page: SidebarSelection) {
        guard page == .advanced else {
            selection = page
            return
        }
        navigation.settingsTab = .advanced
        openSettings()
    }
}
