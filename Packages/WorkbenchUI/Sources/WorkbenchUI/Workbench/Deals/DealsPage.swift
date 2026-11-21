import SwiftUI
import WorkbenchCore

/// The team's deals as a board, one column per stage. A deal opens beside the board.
struct DealsPage: View {
    @Environment(DealsModel.self) private var deals
    @State private var open: String?
    @State private var newTitle = ""
    @State private var asking: WorkObject?
    @State private var passing: WorkObject?

    var body: some View {
        Page(title: SidebarSelection.deals.title, subtitle: subtitle) {
            if let problem = deals.problem { ProblemBanner(text: problem, dismiss: deals.dismissProblem) }
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
                    DealDetail(deal: deal, move: move, close: { open = nil }).frame(width: 360)
                }
            }
        }
        .onAppear(perform: deals.refresh)
        .sheet(item: $asking) { deal in ActionRequiredForm(deal: deal, cancel: { asking = nil }) }
        .sheet(item: $passing) { deal in PassedDealForm(deal: deal, cancel: { passing = nil }) }
    }

    private var subtitle: String {
        "\(deals.deals.count) deals. Your moves and notes go to your team's folder; items only to people who can already read them."
    }

    /// "Action required" asks what is needed first and "Rejected" asks why and when to look again; every other stage
    /// is a plain move. A deal already Rejected is not asked again.
    private func move(_ deal: WorkObject, to stage: String) {
        if stage == WorkObject.actionRequired {
            asking = deal
        } else if stage == WorkObject.rejected, !deal.stages.contains(stage) {
            passing = deal
        } else {
            deals.move(deal, to: stage)
        }
    }

    private func create() {
        open = deals.create(title: newTitle)
        newTitle = ""
    }
}
