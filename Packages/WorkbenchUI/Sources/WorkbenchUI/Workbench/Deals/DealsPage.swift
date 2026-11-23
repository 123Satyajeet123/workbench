import SwiftUI
import WorkbenchCore

struct DealsPage: View {
    @Environment(DealsModel.self) private var deals
    @State private var open: String?
    @State private var newTitle = ""

    var body: some View {
        DealMoving { move in board(move: move) }
            .onAppear(perform: deals.refresh)
    }

    private func board(move: @escaping (WorkObject, StageID) -> Void) -> some View {
        Page(intro: .deals, title: SidebarSelection.deals.title, subtitle: subtitle) {
            ProblemSlotBanner(slot: deals.problems)
            AskBox()
            HStack {
                TextField("New deal: company name", text: $newTitle).frame(maxWidth: 280)
                    .onSubmit(create)
                Button("Add deal", action: create).disabled(newTitle.cleaned == nil)
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise", action: deals.refresh)
            }
            HStack(alignment: .top, spacing: Space.l) {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: Space.m) {
                        ForEach(deals.columns) { StageColumn(column: $0, open: $open, move: move) }
                    }
                }
                if let id = open, let deal = deals.deal(id) {
                    DealDetail(deal: deal, move: move, close: { open = nil }).frame(width: 560)
                }
            }
        }
    }

    private var subtitle: String {
        "\(deals.deals.count) deals. Your moves and notes go to your team's folder; items only to people who can already read them."
    }

    private func create() {
        open = deals.create(title: newTitle)
        newTitle = ""
    }
}

/// Gives its content the way to move a deal to a stage. A waiting stage asks what is needed first and a watch stage
/// asks why and when to look again; every other stage is a plain move. A deal already in the watch stage is not asked
/// again.
struct DealMoving<Content: View>: View {
    @ViewBuilder let content: (_ move: @escaping (WorkObject, StageID) -> Void) -> Content
    @Environment(DealsModel.self) private var deals
    @State private var asking: WorkObject?
    @State private var passing: WorkObject?

    var body: some View {
        content(move)
            .sheet(item: $asking) { deal in ActionRequiredForm(deal: deal, cancel: { asking = nil }) }
            .sheet(item: $passing) { deal in PassedDealForm(deal: deal, cancel: { passing = nil }) }
    }

    private func move(_ deal: WorkObject, to stage: StageID) {
        switch deals.meaning(of: stage) {
        case .waiting:
            asking = deal
        case .watch where !deal.stages.contains(stage):
            passing = deal
        default:
            deals.move(deal, to: stage)
        }
    }
}
