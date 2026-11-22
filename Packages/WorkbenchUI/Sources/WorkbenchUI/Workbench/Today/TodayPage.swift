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

/// The sections of Today, in order. A section with nothing in it is not shown; a day with nothing says so.
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
            morningList
            meetings
            team
            projects
            if let brief { YesterdayBrief(brief: brief) }
        }
        .animation(Motion.settle(reduceMotion: reduceMotion), value: model.revision)
    }

    @ViewBuilder private var morningList: some View {
        if model.offersCutoff { CutoffOffer(model: model) }
        if let batch = model.handledBatch { HandledBar(batch: batch, model: model) }
        ForEach(model.sections) { section in
            TodaySection(Self.title(of: section.kind), count: section.lines.count) {
                if section.kind == .waitingOn {
                    ForEach(section.owners) { owner in
                        Text(owner.owner).fontWeight(.semibold)
                        ForEach(owner.needs) { line($0) }
                    }
                } else {
                    ForEach(section.needs) { line($0) }
                }
            }
        }
    }

    private func line(_ need: Need) -> some View {
        FactLine(item: need.item, model: model).transition(.opacity)
    }

    static func title(of kind: MorningSection.Kind) -> String {
        switch kind {
        case .toConfirm: "To confirm"
        case .slipped: "Late"
        case .owe: "What you owe"
        case .findings: "Needs a look"
        case .revisits: "Revisit"
        case .owedToMe: "Owed to you"
        case .waitingOn: "Waiting on others"
        case .news: "Bad news"
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
}

/// The first list offers to mark the old backlog as handled, in one step.
struct CutoffOffer: View {
    let model: TodayModel

    var body: some View {
        HStack(spacing: Space.m) {
            Label(
                "\(model.backlog.count) open \(model.backlog.count == 1 ? "fact is" : "facts are") older than \(model.cutoffDays) days.",
                systemImage: "tray.full"
            )
            .lineLimit(1)
            Button("Mark them as handled", action: model.markBacklogHandled).buttonStyle(.ghost)
            Button("Keep them", action: model.keepBacklog).buttonStyle(.ghost)
            Spacer()
        }
        .textStyle(.callout).foregroundStyle(Tone.attention.color)
    }
}

/// What the bulk "handled" did, and the way back.
struct HandledBar: View {
    let batch: HandledBatch
    let model: TodayModel

    var body: some View {
        HStack(spacing: Space.m) {
            Label("Marked as handled: older than \(batch.olderThanDays) days.", systemImage: "checkmark.circle")
                .lineLimit(1)
            Button("Reopen them", action: model.reopenHandled).buttonStyle(.ghost)
            Spacer()
        }
        .textStyle(.callout).foregroundStyle(Tone.attention.color)
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

/// A person's or a project's summary line. Open it to see the facts it cites, each with its actions; the actions on
/// the line itself apply to all of them.
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
