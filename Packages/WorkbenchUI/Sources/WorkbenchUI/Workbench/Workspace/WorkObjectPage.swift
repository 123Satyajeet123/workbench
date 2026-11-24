import SwiftUI
import WorkbenchCore

/// The page of a work object: a machine's page shows the machine, a deal its detail, and any other kind its children
/// and the facts filed under it.
struct WorkObjectPage: View {
    let id: WorkObjectID
    let open: (SidebarSelection) -> Void
    let close: () -> Void
    @Environment(WorkspaceModel.self) private var workspace
    @Environment(Crew.self) private var crew
    @Environment(DealsModel.self) private var deals

    var body: some View {
        if let helper = crew.helper(page: id) {
            HelperPage(model: helper)
        } else if let object = workspace.object(id) {
            if object.kind == ObjectTypes.deal.id {
                DealMoving { move in
                    DealDetail(deal: deals.deal(id) ?? object, move: move, close: close)
                        .frame(maxWidth: Page<EmptyView, EmptyView>.columnWidth).padding(Space.page)
                }
            } else {
                FolderPage(object: object, open: open)
            }
        } else {
            ContentUnavailableView("This page was deleted", systemImage: "trash")
        }
    }
}

private struct FolderPage: View {
    let object: WorkObject
    let open: (SidebarSelection) -> Void
    @Environment(WorkspaceModel.self) private var workspace
    @Environment(Crew.self) private var crew
    @Environment(TodayModel.self) private var today
    @State private var contents: [WorkObject] = []
    @State private var facts: [Item] = []

    var body: some View {
        Page(title: object.name, subtitle: object.noun) {
            ProblemSlotBanner(slot: workspace.problems)
            let isDocument = object.kind == ObjectTypes.page.id
            if isDocument { PlainPageDocument(page: object.id) }
            let live = contents.filter { !$0.archived }
            if live.isEmpty && facts.isEmpty && !isDocument {
                Text("Nothing here yet. Add a folder or a page from this row's menu in the sidebar.")
                    .foregroundStyle(.supporting)
            }
            if !live.isEmpty { list(live) }
            if !facts.isEmpty {
                Text("Facts · \(facts.count)").textStyle(.headline)
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(facts, id: \.id) { item in
                        if let row = FactRow(item: item, title: today.title(of: item)) {
                            FactCard(row: row, offered: [], hover: { _ in }, open: {}, act: { _ in })
                        }
                    }
                }
            }
            let archived = contents.filter(\.archived)
            if !archived.isEmpty {
                Fold("Archived · \(archived.count)") { list(archived) }.foregroundStyle(.supporting)
            }
        }
        .task(id: Reading(id: object.id, revision: workspace.revision)) {
            contents = workspace.contents(of: object.id)
            facts = workspace.facts(in: object.id)
        }
    }

    private func list(_ objects: [WorkObject]) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ForEach(objects) { child in
                Button {
                    open(crew.page(of: child))
                } label: {
                    Label {
                        Text(child.name)
                    } icon: {
                        if let helper = crew.helper(page: child.id) {
                            Mascot(look: .of(helper.machine), size: Mascot.sidebarSize, mood: helper.mood)
                        } else {
                            Image(systemName: child.symbol)
                        }
                    }
                }
                .buttonStyle(.link)
            }
        }
    }

    private struct Reading: Equatable {
        let id: WorkObjectID
        let revision: Int
    }
}
