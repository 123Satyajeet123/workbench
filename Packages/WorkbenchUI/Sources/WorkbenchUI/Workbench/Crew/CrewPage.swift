import SwiftUI
import WorkbenchCore

/// The crew in plain words: one card per machine, the items waiting for a check, and Mochi's suggestions.
struct CrewPage: View {
    let open: (SidebarSelection) -> Void
    @Environment(RunsModel.self) private var runs

    var body: some View {
        Page(
            intro: .crew, title: SidebarSelection.crew.title,
            subtitle: "What each machine reads, how right it is and what it costs"
        ) {
            CrewBody(open: open)
        }
        .onAppear(perform: runs.refresh)
    }
}

/// The cards of the Crew page, without the page around them.
struct CrewBody: View {
    let open: (SidebarSelection) -> Void
    @Environment(Crew.self) private var crew
    @Environment(RunsModel.self) private var runs
    @Environment(ReviewModel.self) private var review

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            if let problem = crew.problem { ProblemBanner(text: problem, dismiss: crew.dismissProblem) }
            ForEach(crew.crew, id: \.machine.id) { helper in
                MachineCard(helper: helper, facts: facts(of: helper), open: { open(.machine(helper.machine.id)) })
            }
            reviewCard
            MochiProposals(open: open)
        }
    }

    private func facts(of helper: HelperModel) -> CrewCardFacts {
        CrewCardFacts(task: helper.spec.task, runs: runs.runs, quality: runs.quality, now: .now)
    }

    private var reviewCard: some View {
        Card(title: SidebarSelection.review.title, symbol: "checkmark.circle") {
            Text(
                review.items.isEmpty
                    ? "Nothing waits for your check."
                    : "\(review.items.count) \(review.items.count == 1 ? "item waits" : "items wait") for your check. Each check teaches the machines."
            )
            Button("Open Review") { open(.review) }
        }
    }
}

/// One machine: what it reads, its last reading, how right it is, what it cost, and the choice to pause or open it.
private struct MachineCard: View {
    let helper: HelperModel
    let facts: CrewCardFacts
    let open: () -> Void
    @Environment(Crew.self) private var crew

    var body: some View {
        Card(
            title: "\(helper.name) · \(helper.isPaused ? "Paused" : MachineTemplate.of(helper.machine)?.role ?? "")",
            icon: { Mascot(look: .of(helper.machine), size: 22, mood: helper.mood) },
            content: {
                Text("Reads: \(helper.reads)")
                Text(facts.lastReading)
                Text(facts.health).fontWeight(.medium)
                Text(facts.costThisWeek).foregroundStyle(.supporting)
                if let update = crew.update(for: helper) {
                    UpdateBanner(name: helper.name, changes: update.changes) { crew.upgrade(helper) }
                }
                HStack {
                    Button(helper.isPaused ? "Resume" : "Pause") { crew.setPaused(helper, !helper.isPaused) }
                    Button("Open \(helper.name)", action: open).buttonStyle(.primary)
                }
            })
    }
}
