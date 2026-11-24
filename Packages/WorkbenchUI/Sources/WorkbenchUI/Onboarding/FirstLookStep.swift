import SwiftUI
import WorkbenchCore

/// The last step before "You're set": what the machines find in the last days, with the cost shown before it starts.
struct FirstLookStep: View {
    @Environment(OnboardingModel.self) private var onboarding
    @Environment(Crew.self) private var crew
    @State private var look: FirstLookModel?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if let look {
                FirstLookBody(look: look)
            }
        }
        .task {
            look = FirstLookModel(
                crew: crew, template: onboarding.template, prompts: onboarding.prompts, today: WorkDay(containing: .now)
            )
        }
    }
}

struct FirstLookBody: View {
    @Bindable var look: FirstLookModel
    @Environment(OnboardingModel.self) private var onboarding
    @State private var selected: Int64?
    @State private var hovered: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if let problem = look.problem { ProblemBanner(text: problem) }
            switch look.phase {
            case .ready: plan
            case .reading(let day, let count):
                HStack(spacing: Space.s) {
                    ProgressView().controlSize(.small)
                    Text("Reading day \(day) of \(count)").textStyle(.callout).foregroundStyle(.supporting)
                }
            case .done: result
            }
        }
        .onChange(of: look.phase) { onboarding.hasLookedFirst = look.phase == .done }
        .task(id: look.machines.map(\.machine.id)) { await look.estimate() }
    }

    private var plan: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if !look.choosers.isEmpty {
                Text("Choose what each machine reads.").textStyle(.callout).foregroundStyle(.supporting)
                SourceChoices(machines: look.choosers)
            }
            Stepper("The last \(look.days) days", value: $look.days, in: 1...FirstLook.defaultDays)
                .onChange(of: look.days) { Task { await look.estimate() } }
            Text(Self.costLine(look.cost)).textStyle(.callout).foregroundStyle(.supporting)
            Button("Start the first look") { Task { await look.run() } }
                .buttonStyle(.primary).disabled(look.cost.calls == 0)
            Text("Skip it if you prefer. Nothing is read until you start.").textStyle(.callout)
                .foregroundStyle(.supporting)
        }
    }

    static func costLine(_ cost: FirstLookCost) -> String {
        guard cost.calls > 0 else { return "Nothing to read in these days yet." }
        let money = cost.totalUSD.formatted(.currency(code: "USD").precision(.fractionLength(2)))
        let basis = cost.isMeasured ? "from your own runs" : "a guess until a run is measured"
        return "At most \(cost.calls) model calls, about \(money) (\(basis))."
    }

    @ViewBuilder private var result: some View {
        if look.rows.isEmpty {
            Text("Nothing was found in these days.").textStyle(.callout).foregroundStyle(.supporting)
        } else {
            Text("Mark a few right or wrong. They teach the machine that found them.").textStyle(.callout)
                .foregroundStyle(.supporting)
        }
        ForEach(look.shown) { machine in
            if look.shown.count > 1, !machine.rows.isEmpty {
                Text(machine.name).textStyle(.headline).padding(.top, Space.s)
            }
            ForEach(machine.rows) { card($0) }
        }
    }

    private func card(_ row: FirstLookModel.Row) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            FactCard(
                row: row.fact, offered: FactAction.offered(for: row.fact.item, isOpenFact: false),
                isSelected: selected == row.id, isHovered: hovered == row.id,
                hover: { inside in hovered = inside ? row.id : (hovered == row.id ? nil : hovered) },
                open: { selected = row.id },
                act: { look.mark(row, as: $0 == .right ? .confirmed : .rejected) })
            if let triage = row.triage { WhyDisclosure(triage: triage).padding(.leading, Space.m) }
        }
    }
}
