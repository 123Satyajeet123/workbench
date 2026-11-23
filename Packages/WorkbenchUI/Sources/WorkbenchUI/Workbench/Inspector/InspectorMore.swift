import SwiftUI
import WorkbenchCore

/// What the founder can do with a fact beyond a mark: a drafted message, a reminder, a deal. Each is the founder's
/// click; nothing is sent.
struct InspectorMore: View {
    let item: Item
    let helper: HelperModel
    @Environment(ActionsModel.self) private var actions
    @Environment(DealsModel.self) private var deals
    @Environment(\.uiScale) private var scale
    @State private var linked: String?
    @State private var isChoosing = false

    private static let iconColumn: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            draft
            row("Add to Reminders", symbol: "checklist", action: remind)
            row("New deal from this", symbol: "rectangle.stack.badge.plus", action: newDeal)
            row("Add to a deal…", symbol: "rectangle.stack") { isChoosing = true }
                .popover(isPresented: $isChoosing, arrowEdge: .leading) { dealList }
            if let linked {
                Label(linked, systemImage: "checkmark.circle").foregroundStyle(Tone.good.color).text(.meta)
            }
            if let problem = deals.problem { ProblemBanner(text: problem, dismiss: deals.dismissProblem) }
            ActionNotice()
        }
        .onChange(of: item.id) { linked = nil }
        .sheet(item: Binding(get: { actions.draft }, set: { actions.draft = $0 })) { DraftSheet(draft: $0) }
    }

    private var isActionable: Bool { item.id != nil && item.state != .rejected }

    @ViewBuilder private var draft: some View {
        if actions.drafting == item.id {
            HStack(spacing: Space.s) {
                ProgressView().controlSize(.small).frame(width: Self.iconColumn * scale)
                Text("Drafting a message…")
            }
            .padding(.horizontal, Space.s).padding(.vertical, Space.xs)
        } else {
            row("Draft a message…", symbol: "square.and.pencil") {
                Task { await actions.draft(item, from: helper.machine) }
            }
        }
    }

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
        Task { await actions.remind(item, from: helper.machine, title: item[helper.spec.title]) }
    }

    private func newDeal() {
        deals.dismissProblem()
        Task {
            if await deals.newDeal(from: item, of: helper) != nil && deals.problem == nil {
                linked = "Made a new deal from this."
            }
        }
    }

    private func add(to deal: WorkObject) {
        isChoosing = false
        deals.dismissProblem()
        Task {
            await deals.link(item, from: helper, to: deal.id)
            if deals.problem == nil { linked = "Added to \(deal.title)." }
        }
    }
}
