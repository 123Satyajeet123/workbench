import SwiftUI
import WorkbenchCore

/// One column of the board. A card moves by drag or from its menu.
struct StageColumn: View {
    let column: DealBoard.Column
    @Binding var open: String?
    let move: (WorkObject, String) -> Void
    @Environment(DealsModel.self) private var deals

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("\(column.stage) · \(column.deals.count)").textStyle(.headline)
            ForEach(column.deals) { deal in
                Button {
                    open = deal.id
                } label: {
                    DealCard(deal: deal, digest: deals.digests[deal.id])
                }
                .buttonStyle(.plain)
                .draggable(deal.id)
                .contextMenu { moveMenu(deal) }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 220, alignment: .topLeading)
        .frame(minHeight: 120, alignment: .topLeading)
        .dropDestination(for: String.self) { ids, _ in
            guard let deal = ids.compactMap(deals.deal).first else { return false }
            move(deal, column.stage)
            return true
        }
    }

    @ViewBuilder private func moveMenu(_ deal: WorkObject) -> some View {
        Menu("Move to") {
            ForEach(deals.stages, id: \.self) { stage in Button(stage) { move(deal, stage) } }
        }
        Button(deal.holder == deals.me ? "Let go" : "Take it") {
            deal.holder == deals.me ? deals.release(deal) : deals.claim(deal)
        }
    }
}

/// A deal on the board: its class, owner, open action and capture ribbon.
struct DealCard: View {
    let deal: WorkObject
    let digest: DealDigest?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack {
                Text(deal.title).fontWeight(.medium)
                Spacer(minLength: Space.xs)
                if let rating = digest?.triage?.rating {
                    Text(rating.rawValue.capitalized).textStyle(.caption, weight: .semibold)
                        .foregroundStyle(rating.tone.color)
                }
            }
            if deal.stages.count > 1 {
                Label("Two stages: \(deal.stages.joined(separator: " and "))", systemImage: "exclamationmark.triangle")
                    .textStyle(.caption).foregroundStyle(Tone.attention.color)
            }
            Text(deal.holder.map { "Owner: \($0)" } ?? "No owner").textStyle(.caption).foregroundStyle(.supporting)
            if let action = digest?.action { ActionLine(action: action) }
            if let revisit = digest?.revisit { RevisitLine(revisit: revisit) }
            if let signal = digest?.signals.first { SignalLine(signal: signal, showsQuote: false) }
            if let ribbon = digest?.story.ribbon { CaptureRibbon(ribbon: ribbon) }
        }
        .padding(Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: Radius.card))
    }
}

/// When the investor will look at a passed deal again.
struct RevisitLine: View {
    let revisit: Item

    var body: some View {
        Label(
            "Revisit \(revisit.dueDay?.start.formatted(date: .abbreviated, time: .omitted) ?? "")",
            systemImage: "arrow.counterclockwise"
        )
        .textStyle(.caption, weight: .medium).foregroundStyle(.supporting)
    }
}

/// What the deal waits for and by when. A due date that has passed shows as a warning.
struct ActionLine: View {
    let action: Item

    var body: some View {
        Label("\(action["text"]) · \(due)", systemImage: "flag.fill")
            .textStyle(.caption, weight: .medium).foregroundStyle(isLate ? Tone.bad.color : Tone.attention.color)
    }

    private var isLate: Bool { action.dueDay.map { $0 < WorkDay(containing: .now) } ?? false }

    private var due: String {
        action.dueDay.map { "due \($0.start.formatted(date: .abbreviated, time: .omitted))" } ?? "no date"
    }
}
