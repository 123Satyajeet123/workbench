import SwiftUI
import WorkbenchCore

struct TodayPage: View {
    @Environment(TodayModel.self) private var today
    @Environment(MochiModel.self) private var mochi
    @Environment(IdentityModel.self) private var identity

    var body: some View {
        Page(
            intro: .day,
            title: identity.identity.greeting(), subtitle: Date.now.formatted(date: .complete, time: .omitted),
            look: SidebarSelection.day.look
        ) {
            TodayBody(model: today, brief: mochi.brief)
        }
        .onAppear(perform: today.refresh)
        .task { await today.refreshMeetings() }
        .task(id: today.today) { await today.summarizeIfMissing() }
    }
}

struct TodayBody: View {
    let model: TodayModel
    let brief: MorningBrief?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            ProblemSlotBanner(slot: model.problems)
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
        if let refusal = model.meetings.refusal { PermissionNotice(message: refusal, pane: .calendars) }
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
        }
    }

    private func tone(_ reason: Need.Reason) -> Tone {
        switch reason {
        case .act: .bad
        case .watch, .asks, .due: .attention
        }
    }
}

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

struct SummaryLineRow: View {
    let row: SummaryRow
    let model: TodayModel
    let showsOpenCount: Bool

    var body: some View {
        Fold {
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

struct UndoBar: View {
    let undo: TodayModel.Undo
    let model: TodayModel

    var body: some View {
        HStack(spacing: Space.m) {
            Label(undo.text, systemImage: "arrow.uturn.backward.circle").lineLimit(1)
            Button("Undo", action: model.undo).buttonStyle(.ghost)
            Spacer()
            Button("Dismiss", action: model.dismissUndo).buttonStyle(.ghost)
        }
        .textStyle(.callout).foregroundStyle(Tone.attention.color)
    }
}

private struct YesterdayBrief: View {
    let brief: MorningBrief

    var body: some View {
        Fold("Yesterday's brief · \(brief.day)") {
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
