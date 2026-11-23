import SwiftUI
import WorkbenchCore

struct MochiPage: View {
    let open: (SidebarSelection) -> Void

    @Environment(Crew.self) private var crew
    @Environment(Navigation.self) private var navigation
    @Environment(CaptureSettings.self) private var capture
    @Environment(RunsModel.self) private var runs
    @Environment(IdentityModel.self) private var identity

    var body: some View {
        Page(
            intro: .mochi,
            title: identity.identity.greeting(), subtitle: Date.now.formatted(date: .complete, time: .omitted),
            look: SidebarSelection.day.look
        ) {
            BriefCard()
            if let timeline = crew.timeline { TimelineSection(model: timeline) }
            TeamCard(open: open)
            Card(
                title: "\(SidebarSelection.calls.title) · \(SidebarSelection.calls.role)",
                icon: {
                    SidebarSelection.calls.look.map { Mascot(look: $0, size: 22) }
                }
            ) {
                echoStatus
                Button("Open \(SidebarSelection.calls.title)") { open(.calls) }
            }
            Card(title: "Model use", symbol: "gauge.with.dots.needle.33percent") {
                Text("\(runs.meter.today.tokensText) tokens · \(runs.meter.today.costText) today")
                Button("Open \(SidebarSelection.usage.title)") { open(.usage) }
            }
            Card(title: "Capture", symbol: capture.status.symbol) {
                Text(
                    "Capture is \(capture.status.title.lowercased()). \(capture.log.count) windows and files kept today."
                )
                Button("Open capture settings") { navigation.openSettings(.capture) }
            }
        }
        .onAppear {
            runs.refresh()
            capture.refreshLog()
        }
    }

    @ViewBuilder private var echoStatus: some View {
        if let call = capture.call { RecordingNowLabel(call: call) }
        let finished = capture.recordings(since: Calendar.current.startOfDay(for: .now)).filter {
            $0.state != .recording
        }
        if finished.isEmpty, capture.call == nil {
            Text("No call recorded today. Start one from the menu bar.").foregroundStyle(.supporting)
        } else if !finished.isEmpty {
            let failed = finished.filter { $0.state == .failed }.count
            Text("\(finished.count) calls recorded today\(failed == 0 ? "." : ", \(failed) failed.")")
                .foregroundStyle(failed == 0 ? Color.primary : Tone.bad.color)
        }
    }
}

private struct TeamCard: View {
    let open: (SidebarSelection) -> Void
    @Environment(TeamModel.self) private var team
    @Environment(Crew.self) private var crew
    @Environment(Navigation.self) private var navigation

    var body: some View {
        Card(title: team.team.name.cleaned ?? "Your team", symbol: "person.3") {
            if team.team.people.isEmpty {
                Text("No team yet. Tick your team's people on \(pip?.name ?? "Pip")'s page.").foregroundStyle(
                    .supporting)
            } else {
                Text(
                    team.team.people.map { $0.role.isEmpty ? $0.name : "\($0.name) (\($0.role))" }.formatted(
                        .list(type: .and)))
            }
            if let pip { Button("Edit team on \(pip.name)'s page") { open(.machine(pip.machine.id)) } }
        }
        .onAppear(perform: team.reload)
    }

    private var pip: HelperModel? { crew.team }
}

private struct TimelineSection: View {
    let model: HelperModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Timeline").textStyle(.title2, weight: .bold)
                Spacer()
                DayStepper(day: model.day, today: model.today, show: model.show)
            }
            HelperContent(model: model)
        }
    }
}

private struct BriefCard: View {
    @Environment(MochiModel.self) private var mochi

    var body: some View {
        Card(title: title, symbol: "sun.horizon") {
            if let brief = mochi.brief {
                Text(brief.headline).textStyle(.headline)
                ForEach(Array(brief.lines.enumerated()), id: \.offset) { _, line in
                    Label(
                        line.basis == .inferred ? "\(line.text) (inferred)" : line.text, systemImage: symbol(line.kind)
                    )
                    .foregroundStyle(line.kind == .stuck || line.kind == .ask ? Tone.attention.color : .primary)
                    .help("From \(line.cites.count) item\(line.cites.count == 1 ? "" : "s") your machines found.")
                }
                if !brief.unseen.isEmpty {
                    Text("Not seen: \(brief.unseen.joined(separator: ", ")) found nothing that day.")
                        .textStyle(.callout).foregroundStyle(.supporting)
                }
            } else {
                Text("No brief yet. Mochi writes one each morning when it is on in Settings › Reminders.")
                    .foregroundStyle(.supporting)
            }
            if let problem = mochi.briefProblem { Text(problem).textStyle(.callout).foregroundStyle(.supporting) }
            Button(mochi.briefPhase == .reading ? "Writing…" : "Brief yesterday now") {
                Task { await mochi.writeBrief(for: WorkDay(containing: .now).adding(days: -1)) }
            }
            .disabled(mochi.briefPhase == .reading)
        }
    }

    private var title: String { mochi.brief.map { "Brief of \($0.day)" } ?? "Morning brief" }

    private func symbol(_ kind: MorningBrief.Line.Kind) -> String {
        switch kind {
        case .ask: "person.wave.2"
        case .happened: "checkmark.circle"
        case .stuck: "exclamationmark.triangle"
        case .next: "arrow.right.circle"
        }
    }
}
