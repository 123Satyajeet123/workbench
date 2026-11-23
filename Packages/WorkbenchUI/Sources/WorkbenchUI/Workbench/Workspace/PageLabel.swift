import SwiftUI

/// The name and icon of any page of the window: a fixed helper's or a machine's face, a work object's kind.
struct PageLabel: View {
    let page: SidebarSelection
    @Environment(Crew.self) private var crew
    @Environment(WorkspaceModel.self) private var workspace

    var body: some View {
        Label {
            Text(title)
        } icon: {
            if let look {
                Mascot(look: look, size: SidebarRowFont.iconSize, mood: mood)
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

    private var helper: HelperModel? {
        if case .machine(let id) = page { crew.helper(id: id) } else { nil }
    }

    private var look: Mascot.Look? { helper.map { .of($0.machine) } ?? page.look }

    private var mood: Mascot.Mood { helper?.mood ?? .calm }

    private var symbol: String {
        switch page {
        case .page(let id): workspace.object(id)?.symbol ?? "doc.text"
        default: page.symbol
        }
    }
}
