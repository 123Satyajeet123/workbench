import SwiftUI
import WorkbenchCore

/// One fact with its proof: the person's words, the chat lines they came from, the marks, what else to do with it, and
/// how it came to be. It reads the proof of the fact it is given and follows the fact when it changes.
struct InspectorView<Actions: View>: View {
    static var widths: ClosedRange<CGFloat> { 320...420 }

    let item: Item?
    var isHistoryOpen = false
    @ViewBuilder let actions: Actions
    @Environment(ProofModel.self) private var proof
    @Environment(TeamModel.self) private var team

    var body: some View {
        ScrollView {
            if let item {
                InspectorContent(
                    item: item, card: proof.card(for: item), helper: proof.helper(of: item),
                    offersDeals: InspectorMore.offersDeals(in: team.template), isHistoryOpen: isHistoryOpen,
                    actions: { actions }
                )
                .id(item.id)
            } else {
                Text("Choose a fact to see where it came from.").text(.meta).padding(Space.l)
            }
        }
        .frame(minWidth: Self.widths.lowerBound, maxWidth: Self.widths.upperBound)
        .background(.pageFill)
        .task(id: item) {
            if let item { await proof.load(item) } else { proof.clear() }
        }
    }
}

/// The inspector for one fact, from values: no model is read here.
struct InspectorContent<Actions: View>: View {
    let item: Item
    let card: InspectorCard
    let helper: HelperModel?
    var offersDeals = false
    var isHistoryOpen = false
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            header
            VStack(alignment: .leading, spacing: Space.s) {
                Text(card.source).text(.meta)
                ProofLines(content: card.proof)
            }
            actions
            if let helper {
                InspectorMore(
                    item: item, helper: helper, reminderTitle: card.headline.plain, offersDeals: offersDeals)
            }
            if !card.history.isEmpty { history }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            card.headline.text.textStyle(.body).foregroundStyle(.bodyText).lineLimit(3)
            if !card.meta.isEmpty { Text(card.meta).text(.meta) }
        }
        .accessibilityElement(children: .combine)
    }

    private var history: some View {
        Fold(
            isOpen: isHistoryOpen,
            content: {
                VStack(alignment: .leading, spacing: Space.xs) {
                    ForEach(card.history, id: \.self) { Text($0).text(.meta) }
                }
                .padding(.top, Space.xs)
            },
            label: { Text("History").text(.sectionTitle) })
    }
}
