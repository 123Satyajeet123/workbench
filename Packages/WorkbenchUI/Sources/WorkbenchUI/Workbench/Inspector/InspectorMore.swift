import SwiftUI
import WorkbenchCore

/// What the founder can do with a fact beyond a mark: a reminder, and a deal when the team keeps deals. Each is the
/// founder's click.
struct InspectorMore: View {
    let item: Item
    let helper: HelperModel
    let reminderTitle: String
    let offersDeals: Bool
    @Environment(ActionsModel.self) private var actions
    @Environment(DealsModel.self) private var deals
    @Environment(\.uiScale) private var scale
    @State private var linked: String?
    @State private var isChoosing = false

    /// A team that keeps deals has a deal kind in its template.
    static func offersDeals(in template: TeamTemplate) -> Bool {
        template.objectTypes.contains { $0.id == ObjectTypes.deal.id }
    }

    private static let iconColumn: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            row("Add to Reminders", symbol: "checklist", action: remind)
            if offersDeals {
                row("New deal from this", symbol: "rectangle.stack.badge.plus", action: newDeal)
                row("Add to a deal…", symbol: "rectangle.stack") { isChoosing = true }
                    .popover(isPresented: $isChoosing, arrowEdge: .leading) { dealList }
            }
            if let linked {
                Label(linked, systemImage: "checkmark.circle").foregroundStyle(Tone.good.color).text(.meta)
            }
            if let problem = deals.problem { ProblemBanner(text: problem, dismiss: deals.problems.dismiss) }
            ActionNotice()
        }
        .onChange(of: item.id) { linked = nil }
    }

    private var isActionable: Bool { item.id != nil && item.state != .rejected }

    private func row(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.s) {
                Image(systemName: symbol).foregroundStyle(.iconTint).frame(width: Self.iconColumn * scale)
                Text(title)
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.ghost)
        .disabled(!isActionable)
    }

    private var dealList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xs) {
                if deals.deals.isEmpty { Text("No deals yet.").text(.meta).padding(Space.s) }
                ForEach(deals.deals) { deal in
                    Button(deal.title) { add(to: deal) }.buttonStyle(.ghost).frame(
                        maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(Space.s)
        }
        .frame(width: 260).frame(maxHeight: 280).fixedSize(horizontal: false, vertical: true)
    }

    private func remind() {
        Task { await actions.remind(item, from: helper.machine, title: reminderTitle) }
    }

    private func newDeal() {
        deals.problems.dismiss()
        Task {
            if await deals.newDeal(from: item, of: helper) != nil && deals.problem == nil {
                linked = "Made a new deal from this."
            }
        }
    }

    private func add(to deal: WorkObject) {
        isChoosing = false
        deals.problems.dismiss()
        Task {
            await deals.link(item, from: helper, to: deal.id)
            if deals.problem == nil { linked = "Added to \(deal.title)." }
        }
    }
}
