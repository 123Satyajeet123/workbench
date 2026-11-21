import SwiftUI
import WorkbenchCore

/// The home page: what needs you, your team, your projects, and yesterday's brief. Live: it follows every reading.
struct TodayPage: View {
    @Environment(TodayModel.self) private var today
    @Environment(MochiModel.self) private var mochi
    @Environment(IdentityModel.self) private var identity

    var body: some View {
        Page(
            title: greeting, subtitle: Date.now.formatted(date: .complete, time: .omitted),
            look: SidebarSelection.day.look
        ) {
            TodayBody(model: today, brief: mochi.brief)
        }
        .onAppear(perform: today.refresh)
        .task { await today.refreshMeetings() }
        .task(id: today.today) { await today.summarizeIfMissing() }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let part = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        return identity.identity.hasName ? "\(part), \(identity.identity.name)" : part
    }
}

/// The sections of Today, in order. A section with nothing in it is not shown; a day with nothing says so.
struct TodayBody: View {
    let model: TodayModel
    let brief: MorningBrief?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            if let problem = model.problem { ProblemBanner(text: problem, dismiss: model.dismissProblem) }
            if let undo = model.undoable { UndoBar(undo: undo, model: model) }
            if model.isSummarizing {
                Label("Mochi is summarizing…", systemImage: "sparkles").textStyle(.callout).foregroundStyle(.supporting)
            }
            if model.isEmpty { Text("Nothing for today yet.").foregroundStyle(.supporting) }
            needsYou
            meetings
            team
            projects
            if let brief { YesterdayBrief(brief: brief) }
        }
        .animation(Motion.settle(reduceMotion: reduceMotion), value: model.revision)
    }

    @ViewBuilder private var needsYou: some View {
        if !model.needs.isEmpty {
            TodaySection("Needs you", count: model.needs.count) {
                ForEach(model.needs) { need in
                    FactLine(item: need.item, model: model, flag: label(need.reason), flagTone: tone(need.reason))
                        .transition(.opacity)
                }
            }
        }
    }

    @ViewBuilder private var meetings: some View {
        if model.meetings.offersMeetings { MeetingsOffer(model: model) }
        if let refusal = model.meetings.refusal { PermissionNotice(message: refusal, pane: "Privacy_Calendars") }
        if !model.meetingCards.isEmpty { MeetingsSection(model: model) }
    }

    @ViewBuilder private var team: some View {
        if !model.team.isEmpty || !model.unsummarized.isEmpty {
            TodaySection("Team") {
                ForEach(model.team) { SummaryLineRow(row: $0, model: model, showsOpenCount: false) }
                ForEach(model.unsummarized) { PersonFacts(group: $0, model: model) }
            }
        }
    }

    @ViewBuilder private var projects: some View {
        if !model.projects.isEmpty {
            TodaySection("Projects") {
                ForEach(model.projects) { SummaryLineRow(row: $0, model: model, showsOpenCount: true) }
            }
        }
    }

    private func label(_ reason: Need.Reason) -> String {
        switch reason {
        case .act: "Act today"
        case .watch: "Watch"
        case .asks: "Asks you"
        case .due(let day): day < model.today ? "Overdue" : "Due today"
        case .revisit: "Revisit"
        case .news: "Bad news"
        }
    }

    private func tone(_ reason: Need.Reason) -> Tone {
        switch reason {
        case .act: .bad
        case .watch, .asks, .due, .revisit: .attention
        case .news: .bad
        }
    }
}

/// A heading and its lines.
struct TodaySection<Content: View>: View {
    let title: String
    var count: Int?
    @ViewBuilder let content: Content

    init(_ title: String, count: Int? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.count = count
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(title).textStyle(.title2, weight: .bold)
                if let count { Text("\(count)").foregroundStyle(.supporting) }
            }
            content
        }
    }
}

/// A person's or a project's summary line. Open it to see the facts it cites, each with its actions; the actions on
/// the line itself apply to all of them.
struct SummaryLineRow: View {
    let row: SummaryRow
    let model: TodayModel
    let showsOpenCount: Bool

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: Space.xs) {
                ForEach(row.facts) { FactLine(item: $0, model: model).transition(.opacity) }
            }
            .padding(.leading, Space.s)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack(spacing: Space.s) {
                        Text(row.subject).fontWeight(.semibold)
                        if showsOpenCount, row.openCount > 0 {
                            Text("\(row.openCount) open").textStyle(.caption).foregroundStyle(.supporting)
                        }
                    }
                    Text(row.line.text).foregroundStyle(.supporting)
                }
                Spacer(minLength: Space.m)
                FactActions(items: row.facts, summary: row.subject, model: model)
            }
        }
        .transition(.opacity)
    }
}

/// A person's facts of the day, listed plainly while no summary line covers them.
struct PersonFacts: View {
    let group: FactGroup
    let model: TodayModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(group.name.isEmpty ? "No person named" : group.name).fontWeight(.semibold)
            ForEach(group.open + group.rest) { FactLine(item: $0, model: model).transition(.opacity) }
        }
    }
}

/// What the last action did, and the way back.
struct UndoBar: View {
    let undo: TodayModel.Undo
    let model: TodayModel

    var body: some View {
        HStack(spacing: Space.m) {
            Label(undo.text, systemImage: "arrow.uturn.backward.circle").lineLimit(1)
            Button("Undo", action: model.undo).buttonStyle(.borderless)
            Spacer()
            Button("Dismiss", action: model.dismissUndo).buttonStyle(.borderless)
        }
        .textStyle(.callout).foregroundStyle(Tone.attention.color)
    }
}

/// Yesterday's brief, folded.
private struct YesterdayBrief: View {
    let brief: MorningBrief

    var body: some View {
        DisclosureGroup("Yesterday's brief · \(brief.day)") {
            VStack(alignment: .leading, spacing: Space.s) {
                if !brief.headline.isEmpty { Text(brief.headline).textStyle(.headline) }
                ForEach(Array(brief.lines.enumerated()), id: \.offset) { _, line in
                    Text(line.text).foregroundStyle(.supporting)
                }
            }
            .padding(.top, Space.s)
        }
        .textStyle(.headline)
    }
}
