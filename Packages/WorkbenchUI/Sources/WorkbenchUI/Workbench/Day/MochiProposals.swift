import SwiftUI
import WorkbenchCore

struct MochiProposals: View {
    let open: (SidebarSelection) -> Void
    @Environment(MochiModel.self) private var mochi
    @Environment(ModelSettings.self) private var models

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Machines Mochi suggests").textStyle(.title2, weight: .bold)
            HStack(spacing: Space.m) {
                Button("Find repeated work") { Task { await mochi.discover() } }
                    .buttonStyle(.primary)
                    .disabled(!mochi.canDiscover)
                ReadPhaseLabel(phase: mochi.phase, items: "proposals", droppedBecause: "not backed by your days")
            }
            Text(note).textStyle(.callout).foregroundStyle(.supporting)
            if let problem = mochi.problem { ProblemBanner(text: problem, dismiss: mochi.dismissProblem) }
            ForEach(mochi.waiting) { ProposalCard(proposal: $0, open: open) }
        }
        .onAppear(perform: mochi.refresh)
    }

    private var note: String {
        let (accepted, decided) = mochi.acceptance
        let record = decided == 0 ? "" : " You built \(accepted) of the \(decided) you decided on."
        guard mochi.trainingDays >= Mochi.minimumDays else {
            return
                "Mochi needs timeline blocks on \(Mochi.minimumDays) training days; it has \(mochi.trainingDays). Read and mark your days first."
                + record
        }
        return
            "Mochi reads your marked timeline of the last \(MochiModel.days) days (never the days set aside for testing) with \(models.choice.title) and proposes machines for work that repeats."
            + record
    }
}

private struct ProposalCard: View {
    let proposal: Proposal
    let open: (SidebarSelection) -> Void
    @Environment(MochiModel.self) private var mochi

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Mascot(look: Mascot.Look(hue: 0.4, wear: .antenna), size: 22)
                Text(proposal.name).textStyle(.headline)
                Text(MachineTemplate.all.first { $0.spec.task == proposal.template }?.role ?? proposal.template)
                    .textStyle(.caption).foregroundStyle(.supporting)
            }
            Text(proposal.why)
            Text(proposal.brief).textStyle(.callout).foregroundStyle(.supporting).textSelection(.enabled)
            let evidence = mochi.evidence(proposal)
            if !evidence.isEmpty {
                Text(
                    evidence.map {
                        "\($0.fields["task"] ?? $0.quote) (\($0.day.start.formatted(.dateTime.weekday(.abbreviated).day())))"
                    }
                    .joined(separator: " · ")
                )
                .textStyle(.caption).foregroundStyle(.supporting)
            }
            HStack {
                Button("Build it") { if let id = mochi.accept(proposal) { open(.machine(id)) } }
                    .buttonStyle(.primary)
                Button("Not now") { mochi.decide(proposal, .later) }
                Button("Never") { mochi.decide(proposal, .rejected) }
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.calloutFill, in: .rect(cornerRadius: Radius.card))
    }
}
