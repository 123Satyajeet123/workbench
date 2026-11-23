import SwiftUI

/// The name and icon of any page of the window: a fixed helper's face, a machine's symbol, a work object's kind.
struct PageLabel: View {
    let page: SidebarSelection
    @Environment(Crew.self) private var crew
    @Environment(WorkspaceModel.self) private var workspace

    var body: some View {
        Label {
            Text(title)
        } icon: {
            if let look = page.look {
                Mascot(look: look, size: 18)
            } else {
                Image(systemName: symbol)
            }
        }
    }

    private var title: String {
        switch page {
        case .machine(let id): crew.helper(id: id)?.name ?? page.title
        case .page(let id): workspace.object(id)?.name ?? page.title
        default: page.title
        }
    }

    private var symbol: String {
        switch page {
        case .machine(let id): crew.helper(id: id)?.machine.symbol ?? "gearshape.2"
        case .page(let id): workspace.object(id)?.symbol ?? "doc.text"
        default: page.symbol
        }
    }
}
