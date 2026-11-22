import SwiftUI
import WorkbenchCore

struct AdvancedSettingsView: View {
    @Environment(Crew.self) private var crew
    @Environment(RunsModel.self) private var model

    var body: some View {
        Page(
            title: "Advanced",
            subtitle: "Every call to a model, what it cost, and how often you marked its entries right.",
            accessory: { Button("Refresh", systemImage: "arrow.clockwise", action: model.refresh) }
        ) {
            if let problem = model.problem { ProblemBanner(text: problem) }
            meter
            quality
            runs
        }
        .onAppear(perform: model.refresh)
    }

    private var meter: some View {
        Card(title: "Usage", symbol: "gauge.with.dots.needle.33percent") {
            HStack(alignment: .top, spacing: Space.xl) {
                MeterCell(title: "Today", usage: model.meter.today)
                MeterCell(title: "Last 7 days", usage: model.meter.week)
                MeterCell(title: "All time", usage: model.meter.all)
            }
            Text(
                "Cost is at list price, as Claude reports it. On a plan it is what the calls would cost, not what you pay. Codex reports tokens only."
            )
            .textStyle(.callout).foregroundStyle(.supporting)
        }
    }

    private var quality: some View {
        Card(title: "Quality", symbol: "checkmark.seal") {
            if model.quality.isEmpty {
                Text("No finished run yet. Read a day with a helper, then mark what it found.")
                    .foregroundStyle(.supporting)
            } else {
                Grid(alignment: .leading, horizontalSpacing: Space.l, verticalSpacing: Space.s) {
                    GridRow {
                        ForEach(
                            ["Task", "Model", "Prompt", "Runs", "Dropped", "Right", "Held-out", "Audited", "Trust"],
                            id: \.self
                        ) {
                            Text($0).textStyle(.callout, weight: .semibold).foregroundStyle(.supporting)
                        }
                    }
                    ForEach(model.quality) { row in
                        GridRow {
                            Text(crew.name(ofTask: row.task))
                            Text(row.model)
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
                                Label("Earned", systemImage: "checkmark.shield").foregroundStyle(Tone.good.color)
                            case .needsMore(let more): Text("\(more) more").foregroundStyle(.supporting)
                            }
                        }
                    }
                }
                Text(
                    "Right is the share of your marks that say right. Held-out days (3 in 10, fixed by date) only judge a prompt; they never shape one. Audited counts only your answers to the item each reading picked at random, so it is the fair number."
                )
                .textStyle(.callout).foregroundStyle(.supporting)
            }
        }
    }

    private var runs: some View {
        Card(title: "Calls", symbol: "list.bullet") {
            if model.runs.isEmpty {
                Text("No call yet.").foregroundStyle(.supporting)
            }
            ForEach(model.runs) { RunRow(run: $0) }
        }
    }
}

private struct MeterCell: View {
    let title: String
    let usage: Usage

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title).textStyle(.callout).foregroundStyle(.supporting)
            Text(usage.tokensText + " tokens").textStyle(.title2, weight: .semibold).monospacedDigit()
            Text(usage.costText).monospacedDigit().foregroundStyle(.supporting)
        }
        .accessibilityElement(children: .combine)
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
                Text("\(crew.name(ofTask: run.task)) · \(run.model)")
                Text(detail).textStyle(.callout).foregroundStyle(.supporting)
                if let error = run.error { Text(error).textStyle(.callout).foregroundStyle(Tone.bad.color) }
            }
            Spacer()
            Text(run.startedAt.formatted(date: .abbreviated, time: .shortened)).textStyle(.callout)
                .foregroundStyle(.supporting).monospacedDigit()
        }
    }

    private var detail: String {
        var parts = ["\(run.usage.tokensText) tokens", run.usage.costText]
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
        }
    }

    var tone: Tone {
        switch self {
        case .running: .neutral
        case .done: .good
        case .failed: .bad
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
