import SwiftUI

struct WorkbenchView: View {
    static let minimumSize = CGSize(width: 900, height: 600)
    static let idealSize = CGSize(width: 1160, height: 780)

    @SceneStorage("selection") private var selection = SidebarSelection.day
    @Environment(Crew.self) private var crew
    @Environment(Navigation.self) private var navigation

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $selection)
        } detail: {
            switch selection {
            case .day: TodayPage()
            case .people: FactGroupsPage(lens: .people)
            case .projects: FactGroupsPage(lens: .projects)
            case .mochi: MochiPage(open: { selection = $0 })
            case .machine(let id):
                if let helper = crew.helper(id: id) {
                    HelperPage(model: helper)
                } else {
                    ContentUnavailableView("This machine was deleted", systemImage: "trash")
                }
            case .calls: CallsPage()
            case .runs: RunsPage()
            case .review: ReviewPage()
            case .deals: DealsPage()
            case .catalog: TeamCatalogPage(open: { selection = $0 })
            }
        }
        .frame(
            minWidth: Self.minimumSize.width, idealWidth: Self.idealSize.width, minHeight: Self.minimumSize.height,
            idealHeight: Self.idealSize.height
        )
        .onChange(of: navigation.requested, initial: true) { _, page in
            guard let page else { return }
            selection = page
            navigation.requested = nil
        }
    }
}
