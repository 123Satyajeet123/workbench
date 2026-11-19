import LocalSources
import SwiftUI
import WorkbenchCore

/// A crew helper's page: its face and name, the day, and the helper's content.
struct HelperPage: View {
    let page: SidebarSelection
    let model: HelperModel

    var body: some View {
        Page(
            title: page.title, subtitle: subtitle, look: page.look,
            accessory: { DayStepper(day: model.day, today: model.today, show: model.show) },
            content: { HelperContent(model: model) })
    }

    private var subtitle: String {
        guard case .whatsapp(let source) = model.source, let chat = source.chat else { return page.role }
        return "\(page.role) · \(chat.name)"
    }
}

/// Everything a helper shows for one day: its setup until it is ready, then the read button, the nudge and the
/// items in the view its spec names.
struct HelperContent: View {
    let model: HelperModel
    @Environment(ModelSettings.self) private var models

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            if let problem = model.problem { ProblemBanner(text: problem, dismiss: model.dismissProblem) }
            if case .whatsapp(let source) = model.source, source.chat == nil {
                GroupChooser(model: model, source: source)
            } else {
                controls
                if let question = model.question { Question(model: model, item: question) }
                if model.spec.nudge != nil { NudgeRow(model: model) }
                switch model.spec.view {
                case .board(let field, let expected): Board(model: model, field: field, expected: expected)
                case .timeline: ForEach(model.items) { ItemRow(model: model, item: $0, showsSpan: true) }
                }
            }
        }
        .task(id: model.scope) { await loadMembers() }
        .onAppear(perform: model.reload)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.m) {
                Button("Read this day") { Task { await model.read() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.phase == .reading || noScreenActivity)
                ReadPhaseLabel(
                    phase: model.phase, items: model.spec.itemsNoun, droppedBecause: "not backed by the source")
            }
            Text(note).font(.callout).foregroundStyle(.supporting)
        }
    }

    private var noScreenActivity: Bool {
        if case .screen = model.source { model.sessions.isEmpty } else { false }
    }

    private var note: String {
        switch model.source {
        case .whatsapp:
            return "Reading sends this day's messages to \(models.choice.title). Each call is on the Runs page."
        case .screen:
            guard !model.sessions.isEmpty else {
                return "No screen activity on this day. Turn on Screen in Settings › Capture."
            }
            let minutes = model.sessions.reduce(0) { $0 + $1.minutes }
            return
                "\(model.sessions.count) windows, \(minutes / 60) h \(minutes % 60) min on screen. Reading sends their titles and addresses to \(models.choice.title); never the text on screen."
        }
    }

    private func loadMembers() async {
        guard case .whatsapp(let source) = model.source else { return }
        do {
            try await source.loadMembers()
        } catch {
            model.attempt("read the group members") { throw error }
        }
    }
}

/// The one item the app picked from the last reading. Answering it measures the helper without your choice of what
/// to check.
private struct Question: View {
    let model: HelperModel
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Label("\(model.name) asks: is this right?", systemImage: "questionmark.bubble").font(.headline)
            ItemRow(model: model, item: item, showsSpan: model.spec.citation == .range)
            Text("Picked at random from this reading, so your answer shows how often \(model.name) is right.")
                .font(.callout).foregroundStyle(.supporting)
            if let trust = model.trust { TrustLine(name: model.name, status: trust) }
        }
        .padding(Space.m)
        .background(Tone.attention.color.opacity(0.08), in: .rect(cornerRadius: Radius.card))
    }
}

/// Progress toward trust: the exact binomial bound from audit answers on held-out days.
struct TrustLine: View {
    let name: String
    let status: Certificate.Status

    var body: some View {
        switch status {
        case .earned(let bound):
            Label(
                "\(name) has earned trust: wrong at most \(bound.formatted(.percent.precision(.fractionLength(1)))) of the time, 90% sure.",
                systemImage: "checkmark.shield"
            )
            .foregroundStyle(Tone.good.color).font(.callout)
        case .needsMore(let more):
            Text(
                "\(name) earns trust at most 10% wrong, 90% sure. It needs at least \(more) more right answers on held-out days."
            )
            .font(.callout).foregroundStyle(.supporting)
        }
    }
}

private struct GroupChooser: View {
    let model: HelperModel
    let source: WhatsAppSource

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(
                "Choose your team's WhatsApp group. \(model.name) reads only that group, and only the day you ask it to read."
            )
            .foregroundStyle(.supporting)
            if source.groups.isEmpty {
                Button("Show my WhatsApp groups") { model.attempt("list your WhatsApp groups", source.loadGroups) }
                    .buttonStyle(.borderedProminent)
            }
            ForEach(source.groups) { group in
                HStack {
                    Text(group.name)
                    Spacer()
                    Button("Choose") {
                        model.attempt("save the group") { try source.choose(group) }
                        model.reload()
                    }
                }
                Divider()
            }
        }
    }
}

/// One section per value of a field. Every name the helper expects is shown, with a note when it has no item.
private struct Board: View {
    let model: HelperModel
    let field: String
    let expected: String

    var body: some View {
        ForEach(groups, id: \.self) { group in
            let own = model.items.filter { $0[field] == group }
            VStack(alignment: .leading, spacing: Space.s) {
                Text(group).font(.headline)
                if own.isEmpty {
                    Label("No \(model.spec.itemsNoun)", systemImage: "questionmark.circle")
                        .foregroundStyle(Tone.attention.color)
                }
                ForEach(own) { ItemRow(model: model, item: $0, showsSpan: false) }
            }
            Divider()
        }
    }

    /// Expected names first, in their order; then any other value an item names.
    private var groups: [String] {
        let names = model.context[expected] ?? []
        return names + Set(model.items.map { $0[field] }).subtracting(names).sorted()
    }
}

private struct ItemRow: View {
    let model: HelperModel
    let item: Item
    let showsSpan: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            if showsSpan {
                Text(span).font(.callout.monospacedDigit()).foregroundStyle(.supporting)
                    .frame(width: 110, alignment: .leading)
            } else if let (value, tone) = toned {
                Image(systemName: tone.symbol).foregroundStyle(tone.color).frame(width: 18).accessibilityLabel(value)
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.s) {
                    Text(item[model.spec.title])
                    ForEach(model.spec.badges.map { item[$0] }.filter { !$0.isEmpty }, id: \.self) { badge in
                        Text(badge).font(.caption).padding(.horizontal, Space.s).padding(.vertical, 2)
                            .background(.quaternary, in: .capsule)
                    }
                }
                Text(showsSpan ? "“\(item.quote)”" : "“\(item.quote)” · \(time(item.start))")
                    .font(.callout).foregroundStyle(.supporting).textSelection(.enabled)
            }
            .opacity(item.state == .rejected ? 0.5 : 1)
            .strikethrough(item.state == .rejected)
            Spacer()
            MarkButtons(state: item.state) { model.mark(item, as: $0) }
        }
    }

    /// The value of the first field whose values carry a tone, and that tone.
    private var toned: (String, HelperSpec.Tone)? {
        for field in model.spec.fields {
            if let tone = model.spec.tones[item[field.name]] { return (item[field.name], tone) }
        }
        return nil
    }

    private var span: String { "\(time(item.start))–\(time(item.end))" }

    private func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }
}

/// The once-a-day nudge: on or off, and its time.
private struct NudgeRow: View {
    let model: HelperModel
    @Environment(ModelSettings.self) private var models

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.m) {
                Toggle(
                    "Night nudge",
                    isOn: Binding(get: { model.nudge.isOn }, set: { on in Task { await model.setNudge(on: on) } }))
                DatePicker("at", selection: time, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .disabled(!model.nudge.isOn)
            }
            Text(
                "At this time \(model.name) reads today with \(models.choice.title) and tells you who has no \(model.spec.itemsNoun). Silent; the Mac must be on."
            )
            .font(.callout).foregroundStyle(.supporting)
        }
    }

    private var time: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: model.nudge.hour, minute: model.nudge.minute, second: 0, of: .now)
                    ?? .now
            },
            set: {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
                model.nudge.hour = parts.hour ?? model.nudge.hour
                model.nudge.minute = parts.minute ?? model.nudge.minute
            })
    }
}

extension HelperSpec.Tone {
    var color: Color {
        switch self {
        case .good: Tone.good.color
        case .attention: Tone.attention.color
        case .bad: Tone.bad.color
        case .neutral: Tone.neutral.color
        }
    }

    var symbol: String {
        switch self {
        case .good: "checkmark.seal.fill"
        case .attention: "exclamationmark.circle.fill"
        case .bad: "exclamationmark.octagon.fill"
        case .neutral: "circle.dashed"
        }
    }
}
