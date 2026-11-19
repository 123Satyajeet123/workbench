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
            TimelineSection(model: crew.timeline)
            HelperCard(page: .team, open: open) { pipStatus }
            HelperCard(page: .calls, open: open) { echoStatus }
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

    @ViewBuilder private var pipStatus: some View {
        let team = crew.team
        if case .whatsapp(let source) = team.source, let chat = source.chat {
            let missing = team.missing(on: team.today)
            Text("\(chat.name): \(team.items(on: team.today).count) \(team.spec.itemsNoun) today.")
            if !missing.isEmpty {
                Text("No update yet from \(missing.formatted(.list(type: .and))).").foregroundStyle(
                    Tone.attention.color)
            }
            if team.nudge.isOn {
                Text("Night nudge at \(String(format: "%02d:%02d", team.nudge.hour, team.nudge.minute)).")
                    .foregroundStyle(.supporting)
            }
        } else {
            Text("No team group chosen yet.").foregroundStyle(.supporting)
        }
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

/// A crew helper on Mochi's page: its face, its role, what it has for you, and a way to open it.
private struct HelperCard<Status: View>: View {
    let page: SidebarSelection
    let open: (SidebarSelection) -> Void
    @ViewBuilder let status: Status

    var body: some View {
        Card(
            title: "\(page.title) · \(page.role)", icon: { page.look.map { Mascot(look: $0, size: 22) } },
            content: {
                status
                Button("Open \(page.title)") { open(page) }
            })
    }
}

/// The day timeline on Mochi's page: a heading with the day, then the helper's content.
private struct TimelineSection: View {
    let model: HelperModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Timeline").font(.title2.bold())
                Spacer()
                DayStepper(day: model.day, today: model.today, show: model.show)
            }
            HelperContent(model: model)
        }
    }
}
