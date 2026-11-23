import SwiftUI
import WorkbenchCore

struct TrialCard: View {
    let model: HelperModel
    @Environment(Crew.self) private var crew

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Label(
                model.trial?.by == .proposer ? "Mochi proposed a change; it is on trial" : "A new version is on trial",
                systemImage: "flask"
            )
            .textStyle(.headline)
            if let why = model.trial?.why, !why.isEmpty {
                Text("Why: \(why)").textStyle(.callout)
            }
            if model.trialPhase == .reading {
                ProgressView("Reading past days with the new brief…").controlSize(.small)
            } else if let trial = model.trial {
                Text(summary(trial.result, days: trial.days.count))
                Text(verdict(trial.result)).fontWeight(.medium)
                    .foregroundStyle(
                        trial.result.verdict == .better
                            ? Tone.good.color : trial.result.verdict == .worse ? Tone.bad.color : .primary)
                Text(change(trial.version)).textStyle(.callout).foregroundStyle(.supporting).lineLimit(3)
                HStack {
                    Button("Switch to the new brief") { crew.switchToTrial(model) }
                    Button("Keep the current brief", action: model.keepCurrent)
                }
            }
        }
        .calloutBox()
    }

    private func change(_ version: HelperModel.Version) -> String {
        var parts: [String] = []
        if version.brief != model.spec.brief { parts.append("New brief: “\(version.brief)”") }
        if version.examples != model.spec.examples {
            parts.append(version.examples.map { "Sees \($0) of your marked examples" } ?? "No examples")
        }
        if version.runner != model.spec.runner {
            parts.append("Reads with \(version.runner.flatMap(ModelChoice.with(id:))?.title ?? "your chosen model")")
        }
        return parts.joined(separator: " · ")
    }

    private func summary(_ result: Trial, days: Int) -> String {
        "On \(days) past days: \(result.same) the same, \(result.added.count) new, \(result.dropped.count) no longer given. "
            + (result.waiting == 0 ? "" : "\(result.waiting) new ones wait for your mark in Review.")
    }

    private func verdict(_ result: Trial) -> String {
        switch result.verdict {
        case .better: "Better: right on \(result.better) of the \(result.better + result.worse) differences you marked."
        case .worse: "Worse: wrong on \(result.worse) of the \(result.better + result.worse) differences you marked."
        case .notSure:
            "Not sure yet: better on \(result.better), worse on \(result.worse) of the differences you marked. "
                + "The test stays fair however often you look; mark the waiting items in Review."
        }
    }
}
