import SwiftUI
import WorkbenchCore

/// The loop made visible: how often the founder marked each model call's entries right. The words of the trust method
/// (prompt versions, held-out days, audits) live here and nowhere else.
struct QualitySection: View {
    @Environment(Crew.self) private var crew
    @Environment(RunsModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if model.quality.isEmpty {
                Text("No finished run yet. Read a day with a machine, then mark what it found.")
                    .foregroundStyle(.supporting)
            } else {
                Grid(alignment: .leading, horizontalSpacing: Space.l, verticalSpacing: Space.s) {
                    GridRow {
                        ForEach(
                            ["Task", "Model", "Prompt", "Runs", "Dropped", "Right", "Held-out", "Audited", "Trust"],
                            id: \.self
                        ) {
                            Text($0).textStyle(.callout).foregroundStyle(.supporting)
                        }
                    }
                    ForEach(model.quality) { row in
                        GridRow {
                            Text(crew.usageName(ofTask: row.task))
                            Text(UsageReport.modelName(row.model))
                            Text(row.version.map { "v\($0)" } ?? "–").monospacedDigit().help(row.prompt)
                            Text("\(row.runs)").monospacedDigit()
                            Text("\(row.dropped) of \(row.kept + row.dropped)").monospacedDigit()
                                .help("Items the model gave whose quote was not in the source")
                            TallyText(tally: row.all)
                            TallyText(tally: row.heldOut)
                            Text(
                                row.audited.precision.map {
                                    "\($0.formatted(.percent.precision(.fractionLength(0)))) of \(row.audited.marks)"
                                } ?? "–"
                            )
                            .monospacedDigit().bold()
                            switch row.heldOutAudit.status {
                            case .earned:
                                Label("Earned (provisional)", systemImage: "checkmark.shield").foregroundStyle(
                                    Tone.good.color
                                )
                                .help(TrustWording.limit)
                            case .needsMore(let more): Text("\(more) more clean runs").foregroundStyle(.supporting)
                            }
                        }
                    }
                }
                Text(
                    "Right is the share of your marks that say right. Held-out days (3 in 10, fixed by date) only judge a prompt; they never shape one. Audited counts only your answers to the items the app picked at random (each new item has a \(RunSettings.standard.pickChance.formatted(.percent)) chance), so it is the fair number."
                )
                .textStyle(.callout).foregroundStyle(.supporting)
            }
        }
    }
}

struct CallsSection: View {
    private static let shown = 25

    let runs: [Run]
    @State private var showsAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if runs.isEmpty { Text("No call in this period.").foregroundStyle(.supporting) }
            ForEach(showsAll ? runs : Array(runs.prefix(Self.shown))) { RunRow(run: $0) }
            if !showsAll, runs.count > Self.shown {
                Button("Show all \(runs.count) calls") { showsAll = true }.buttonStyle(.ghost)
                    .foregroundStyle(.linkText)
            }
        }
    }
}

private struct RunRow: View {
    @Environment(Crew.self) private var crew
    let run: Run

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            Image(systemName: run.outcome.symbol).foregroundStyle(run.outcome.tone.color)
                .accessibilityLabel(run.outcome.rawValue)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("\(crew.usageName(ofTask: run.task)) · \(UsageReport.modelName(run.model))")
                Text(detail).textStyle(.callout).foregroundStyle(.supporting)
                if let error = run.error { Text(error).textStyle(.callout).foregroundStyle(Tone.bad.color) }
            }
            Spacer()
            Text(run.startedAt.formatted(date: .abbreviated, time: .shortened)).textStyle(.callout)
                .foregroundStyle(.supporting).monospacedDigit()
        }
    }

    private var detail: String {
        var parts = run.usage.map { ["\($0.tokensText) tokens", $0.costUSD.usageCost] } ?? ["usage not counted"]
        if let ended = run.endedAt {
            parts.append(Duration.seconds(ended.timeIntervalSince(run.startedAt)).formatted(.units(width: .narrow)))
        }
        if let kept = run.kept, let dropped = run.dropped { parts.append("\(kept) kept, \(dropped) dropped") }
        return parts.joined(separator: " · ")
    }
}

extension Run.Outcome {
    var symbol: String {
        switch self {
        case .running: "clock"
        case .done: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .cancelled: "minus.circle"
        }
    }

    var tone: Tone {
        switch self {
        case .running: .neutral
        case .done: .good
        case .failed: .bad
        case .cancelled: .neutral
        }
    }
}

private struct TallyText: View {
    let tally: Tally

    var body: some View {
        Text(
            tally.precision.map { "\($0.formatted(.percent.precision(.fractionLength(0)))) of \(tally.marked)" } ?? "–"
        )
        .monospacedDigit()
    }
}
