import SwiftUI
import WorkbenchCore

struct StageColumn: View {
    let column: ObjectBoard.Column
    @Binding var open: String?
    let move: (WorkObject, StageID) -> Void
    @Environment(DealsModel.self) private var deals

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("\(column.stage.label) · \(column.objects.count)").textStyle(.headline)
            ForEach(column.objects) { deal in
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
            move(deal, column.id)
            return true
        }
    }

    @ViewBuilder private func moveMenu(_ deal: WorkObject) -> some View {
        Menu("Move to") {
            ForEach(deals.stages) { stage in Button(stage.label) { move(deal, stage.id) } }
        }
        Button(deal.holder == deals.me ? "Let go" : "Take it") {
            deal.holder == deals.me ? deals.release(deal) : deals.claim(deal)
        }
    }
}

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
                Label(
                    "Two stages: \(deal.stageLabels.joined(separator: " and "))",
                    systemImage: "exclamationmark.triangle"
                )
                .textStyle(.caption).foregroundStyle(Tone.attention.color)
            }
            Text(deal.holder.map { "Owner: \($0)" } ?? "No owner").textStyle(.caption).foregroundStyle(.supporting)
            if let action = digest?.action { ActionLine(action: action) }
            if let revisit = digest?.revisit { RevisitLine(revisit: revisit) }
            if let signal = digest?.signals.first { SignalLine(signal: signal, showsQuote: false) }
            if let ribbon = digest?.story.ribbon { CaptureRibbon(ribbon: ribbon) }
        }
        .calloutBox(padding: Space.s, fillsWidth: true)
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
