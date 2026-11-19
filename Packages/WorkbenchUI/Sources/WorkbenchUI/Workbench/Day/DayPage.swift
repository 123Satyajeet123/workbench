import SwiftUI
import WorkbenchCore

/// The day helper: one look at the day across the crew, each with a way to open the helper.
struct DayPage: View {
    let open: (SidebarSelection) -> Void

    @Environment(Crew.self) private var crew
    @Environment(CaptureSettings.self) private var capture
    @Environment(RunsModel.self) private var runs
    @Environment(IdentityModel.self) private var identity

    var body: some View {
        Page(
            title: greeting, subtitle: Date.now.formatted(date: .complete, time: .omitted),
            look: SidebarSelection.day.look
        ) {
            BriefCard()
            if let timeline = crew.timeline { TimelineSection(model: timeline) }
            MochiProposals(open: open)
            TeamCard()
            ForEach(crew.crew, id: \.machine.id) { helper in
                MachineCard(helper: helper, open: { open(.machine(helper.machine.id)) })
            }
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
                Button("Open Runs") { open(.runs) }
            }
            Card(title: "Capture", symbol: capture.status.symbol) {
                Text(
                    "Capture is \(capture.status.title.lowercased()). \(capture.log.count) windows and files kept today."
                )
                SettingsLink { Text("Open capture settings") }
            }
        }
        .onAppear {
            runs.refresh()
            capture.refreshLog()
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let part = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        return identity.identity.hasName ? "\(part), \(identity.identity.name)" : part
    }

    @ViewBuilder private var echoStatus: some View {
        if let call = capture.call {
            Label(
                "Recording \(call.app) since \(call.startedAt.formatted(date: .omitted, time: .shortened))",
                systemImage: "record.circle"
            )
            .foregroundStyle(Tone.bad.color)
        }
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

/// A machine on Mochi's page: its face, what it has for you today, and a way to open it.
private struct MachineCard: View {
    let helper: HelperModel
    let open: () -> Void

    var body: some View {
        Card(
            title: "\(helper.name) · \(helper.isPaused ? "Paused" : MachineTemplate.of(helper.machine)?.role ?? "")",
            icon: { Mascot(look: .of(helper.machine), size: 22, mood: helper.mood) },
            content: {
                status
                Button("Open \(helper.name)", action: open)
            })
    }

    @ViewBuilder private var status: some View {
        let today = helper.items(on: helper.today)
        if case .whatsapp(let source) = helper.source, source.chat == nil {
            Text("No group chosen yet.").foregroundStyle(.supporting)
        } else {
            Text("\(today.count) \(helper.spec.itemsNoun) today.")
            let missing = helper.missing(on: helper.today)
            if !missing.isEmpty {
                Text("No update yet from \(missing.formatted(.list(type: .and))).")
                    .foregroundStyle(Tone.attention.color)
            }
            if helper.question != nil {
                Text("\(helper.name) has a question for you.").foregroundStyle(Tone.attention.color)
            }
        }
    }
}

/// The team on Mochi's page: its name and people, with a way to edit them.
private struct TeamCard: View {
    @Environment(TeamModel.self) private var team

    var body: some View {
        Card(title: team.team.name.cleaned ?? "Your team", symbol: "person.3") {
            if team.team.people.isEmpty {
                Text("No team yet. Add your team and its people in Settings.").foregroundStyle(.supporting)
            } else {
                Text(
                    team.team.people.map { $0.role.isEmpty ? $0.name : "\($0.name) (\($0.role))" }.formatted(
                        .list(type: .and)))
            }
            SettingsLink { Text("Edit team") }
        }
    }
}

/// The day timeline on Mochi's page: a heading with the day, then the helper's content.
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

/// Mochi's brief: what happened, what is stuck, what to do first, each line resting on items the machines found.
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
            if let problem = mochi.problem { Text(problem).textStyle(.callout).foregroundStyle(.supporting) }
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
