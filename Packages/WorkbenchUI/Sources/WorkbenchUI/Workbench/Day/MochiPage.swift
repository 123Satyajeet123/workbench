import SwiftUI
import WorkbenchCore

/// The home: Mochi's brief, Mochi's one question, then what needs you, today's meetings, follow-ups from calls, the
/// team and the projects.
struct MochiPage: View {
    @Environment(TodayModel.self) private var today
    @Environment(IdentityModel.self) private var identity

    var body: some View {
        Page(
            intro: .mochi,
            title: identity.identity.greeting(), subtitle: Date.now.formatted(date: .complete, time: .omitted),
            look: SidebarSelection.mochi.look
        ) {
            BriefCard()
            QuestionCard()
            TodayBody(model: today, brief: nil)
        }
        .onAppear(perform: today.refresh)
        .task { await today.refreshMeetings() }
        .task(id: today.today) { await today.summarizeIfMissing() }
    }
}

/// The timeline machine's blocks of work, one day at a time.
struct TimelinePage: View {
    @Environment(Crew.self) private var crew

    var body: some View {
        Page(intro: .timeline, title: SidebarSelection.timeline.title, subtitle: SidebarSelection.timeline.role) {
            if let timeline = crew.timeline {
                HStack {
                    Spacer()
                    DayStepper(day: timeline.day, today: timeline.today, show: timeline.show)
                }
                HelperContent(model: timeline)
            } else {
                Text("The timeline reader is missing.").foregroundStyle(.supporting)
            }
        }
    }
}

/// The one item a machine picked at random for the founder to check, from Review: the answer measures the machine.
private struct QuestionCard: View {
    @Environment(ReviewModel.self) private var review

    var body: some View {
        if let item = review.question {
            Card(
                title: "\(review.name(of: item)) asks: is this right?",
                icon: { review.helper(for: item).map { Mascot(look: .of($0.machine), size: 22) } },
                content: {
                    HStack(alignment: .top, spacing: Space.m) {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text(title(of: item)).fontWeight(.medium)
                            Text(item.quotedWords).textStyle(.callout).foregroundStyle(.supporting)
                                .textSelection(.enabled)
                        }
                        Spacer(minLength: Space.m)
                        MarkButtons(state: item.state) { review.answer(item, $0) }
                    }
                    Text(Self.why).textStyle(.caption).foregroundStyle(.supporting)
                })
        }
    }

    private static let why =
        "Picked at random from its last reading. Your answer is how Workbench measures how right it is."

    private func title(of item: Item) -> String {
        review.helper(for: item).map { item[$0.spec.title] } ?? item.quote
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
                Text("No brief yet. Mochi writes one each morning when it is on in Settings › Notifications.")
                    .foregroundStyle(.supporting)
            }
            if let problem = mochi.briefProblem { Text(problem).textStyle(.callout).foregroundStyle(.supporting) }
            Button(mochi.briefPhase == .reading ? "Writing…" : "Brief yesterday now") {
                Task { await mochi.writeBrief(for: WorkDay(containing: .now).adding(days: -1)) }
            }
            .buttonStyle(.primary)
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
