import SwiftUI
import WorkbenchCore

/// One fact with its proof: why it is here, the chat lines it came from, the marks, what else to do with it, and how it
/// came to be. It reads the proof of the fact it is given and follows the fact when it changes.
struct InspectorView<Actions: View>: View {
    static var widths: ClosedRange<CGFloat> { 320...420 }

    let item: Item?
    /// Why the fact is on the list, in a word: "Overdue", "Asks you".
    var reason: String?
    var reasonTone = Tone.attention
    var isHistoryOpen = false
    @ViewBuilder let actions: Actions
    @Environment(ProofModel.self) private var proof

    var body: some View {
        ScrollView {
            if let item {
                InspectorContent(
                    item: item, card: proof.card(for: item), helper: proof.helper(of: item), reason: reason,
                    reasonTone: reasonTone, isHistoryOpen: isHistoryOpen, actions: { actions }
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
    var reason: String?
    var reasonTone = Tone.attention
    var isHistoryOpen = false
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            header
            VStack(alignment: .leading, spacing: Space.s) {
                Text("Where it came from").text(.sectionTitle)
                Text(card.source).text(.meta)
                ProofLines(content: card.proof)
            }
            actions
            if let helper {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("More").text(.sectionTitle)
                    InspectorMore(item: item, helper: helper)
                }
            }
            if !card.history.isEmpty { history }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if let reason { Chip(reason, tone: reasonTone) }
            Text(card.title).text(.rowTitle).lineLimit(3)
            if !card.meta.isEmpty { Text(card.meta).text(.meta) }
        }
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
