import SwiftUI

struct WorkbenchView: View {
    static let minimumSize = CGSize(width: 900, height: 600)
    static let idealSize = CGSize(width: 1160, height: 780)

    @SceneStorage("selection") private var selection = SidebarSelection.day
    @Environment(Crew.self) private var crew

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $selection)
        } detail: {
            switch selection {
            case .day: DayPage(open: { selection = $0 })
            case .team: HelperPage(page: .team, model: crew.team)
            case .calls: CallsPage()
            case .runs: RunsPage()
            }
        }
        .frame(
            minWidth: Self.minimumSize.width, idealWidth: Self.idealSize.width, minHeight: Self.minimumSize.height,
            idealHeight: Self.idealSize.height)
    }
}
