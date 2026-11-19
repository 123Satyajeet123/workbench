import SwiftUI
import WorkbenchCore

/// The proposer: Mochi reads the founder's marks on training days and puts one clear fix on trial.
struct ImproveRow: View {
    let model: HelperModel
    @State private var asking = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.m) {
                Button(asking ? "Looking at your marks…" : "Improve from my marks") {
                    asking = true
                    Task {
                        await model.improve()
                        asking = false
                    }
                }
                .disabled(asking || model.isPaused)
                .help(
                    "Mochi reads the items you marked on training days and tries one small change on past days. You decide."
                )
                Menu("Try another model") {
                    ForEach(ModelChoice.choices.filter { $0.id != model.spec.runner }) { choice in
                        Button(choice.title) { Task { await model.tryModel(choice) } }
                    }
                }
                .fixedSize().disabled(asking || model.isPaused)
                .help("Reads your marked past days with that model and compares. The days go to that model's maker.")
                if model.spec.examples == nil {
                    Button("Learn from my marked examples") { Task { await model.learnFromMarks() } }
                        .disabled(asking || model.isPaused)
                        .help(
                            "The machine sees a few items you marked on other training days when it reads. It is tried on past days first; you decide."
                        )
                }
                if let note = model.improveNote { Text(note).textStyle(.callout).foregroundStyle(.supporting) }
            }
            DecisionHistory(model: model)
        }
    }
}

/// The machine's last decisions: trials, switches, rejections, rollbacks.
struct DecisionHistory: View {
    let model: HelperModel

    var body: some View {
        let decisions = model.decisions.prefix(5)
        if !decisions.isEmpty {
            DisclosureGroup("History") {
                ForEach(decisions, id: \.logKey) { decision in
                    Text("\(decision.at.formatted(date: .abbreviated, time: .shortened)) · \(line(decision))")
                        .textStyle(.callout).foregroundStyle(.supporting)
                }
            }
            .textStyle(.callout)
        }
    }

    private func line(_ decision: Decision) -> String {
        let who = decision.by == .person ? "you" : decision.by == .proposer ? "Mochi" : "the alarm"
        switch decision.kind {
        case .trial: return "\(who) started a trial"
        case .promote: return "you switched to the new brief"
        case .reject: return "you kept the current brief"
        case .rollback:
            return
                "rolled back by the alarm (\(decision.detail["wrong"] ?? "?") of \(decision.detail["answers"] ?? "?") wrong)"
        }
    }
}

extension Decision {
    /// A decision is logged once and never changed, so when it was made and what it was names it.
    var logKey: String { "\(at.timeIntervalSinceReferenceDate) \(kind.rawValue) \(by.rawValue)" }
}
