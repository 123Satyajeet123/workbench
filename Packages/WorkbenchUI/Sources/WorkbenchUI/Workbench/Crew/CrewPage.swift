import SwiftUI
import WorkbenchCore

struct CrewPage: View {
    let open: (SidebarSelection) -> Void
    @Environment(RunsModel.self) private var runs

    var body: some View {
        Page(
            intro: .crew, title: SidebarSelection.crew.title,
            subtitle: "What each of Mochi's machines reads, how right it is and what it costs"
        ) {
            CrewBody(open: open)
        }
        .onAppear(perform: runs.refresh)
    }
}

struct CrewBody: View {
    let open: (SidebarSelection) -> Void
    @Environment(Crew.self) private var crew
    @Environment(RunsModel.self) private var runs

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            ProblemSlotBanner(slot: crew.problems)
            EchoCard(open: open)
            ForEach(crew.machines, id: \.machine.id) { helper in
                MachineCard(helper: helper, facts: facts(of: helper), open: { open(.machine(helper.machine.id)) })
            }
            MochiProposals(open: open)
        }
    }

    private func facts(of helper: HelperModel) -> CrewCardFacts {
        CrewCardFacts(task: helper.spec.task, runs: runs.runs, quality: runs.quality, now: .now)
    }

}

private struct EchoCard: View {
    let open: (SidebarSelection) -> Void
    @Environment(CaptureSettings.self) private var capture

    var body: some View {
        Card(
            title: "Echo · Calls",
            icon: { SidebarSelection.calls.look.map { Mascot(look: $0, size: 22) } },
            content: {
                Text("Reads: the calls you record")
                status
                Button("Open \(SidebarSelection.calls.title)") { open(.calls) }.buttonStyle(.primary)
            })
    }

    @ViewBuilder private var status: some View {
        if let call = capture.call { RecordingNowLabel(call: call) }
        let finished = capture.recordings(since: Calendar.current.startOfDay(for: .now)).filter {
            $0.state != .recording
        }
        if finished.isEmpty, capture.call == nil {
            Text("No call recorded today.").foregroundStyle(.supporting)
        } else if !finished.isEmpty {
            let failed = finished.filter { $0.state == .failed }.count
            Text("\(finished.count) calls recorded today\(failed == 0 ? "." : ", \(failed) failed.")")
                .foregroundStyle(failed == 0 ? Color.primary : Tone.bad.color)
        }
    }
}

private struct MachineCard: View {
    let helper: HelperModel
    let facts: CrewCardFacts
    let open: () -> Void
    @Environment(Crew.self) private var crew

    var body: some View {
        Card(
            title: "\(helper.name) · \(helper.role)",
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
