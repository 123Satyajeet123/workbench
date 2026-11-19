import LocalSources
import SwiftUI
import WorkbenchCore

/// A machine's page: its face and name, the day, and the machine's content.
struct HelperPage: View {
    let model: HelperModel

    var body: some View {
        Page(
            title: model.name, subtitle: subtitle, look: .of(model.machine),
            accessory: { DayStepper(day: model.day, today: model.today, show: model.show) },
            content: { HelperContent(model: model) })
    }

    private var subtitle: String {
        let role = model.isPaused ? "Paused" : MachineTemplate.of(model.machine)?.role ?? ""
        switch model.source {
        case .whatsapp(let source): return source.chat.map { "\(role) · \($0.name)" } ?? role
        case .pages(let source):
            return source.sites.isEmpty ? role : "\(role) · \(source.sites.joined(separator: ", "))"
        case .screen: return role
        }
    }
}

/// Everything a helper shows for one day: its setup until it is ready, then the read button, the nudge and the
/// items in the view its spec names.
struct HelperContent: View {
    let model: HelperModel
    @Environment(ModelSettings.self) private var models
    @Environment(CaptureSettings.self) private var capture
    @Environment(TeamCatalogModel.self) private var catalog
    @Environment(ActionsModel.self) private var actions

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            if let problem = model.problem { ProblemBanner(text: problem, dismiss: model.dismissProblem) }
            ActionNotice()
            if model.isPaused { PausedNote(model: model) }
            if case .whatsapp(let source) = model.source, source.chat == nil {
                GroupChooser(model: model, source: source)
            } else if case .pages(let source) = model.source, source.sites.isEmpty {
                SiteChooser(model: model, source: source)
            } else {
                controls
                if let question = model.question { Question(model: model, item: question) }
                if let notice = model.notice { NoticeRow(text: notice) { model.notice = nil } }
                if model.trial != nil || model.trialPhase == .reading {
                    TrialCard(model: model)
                } else {
                    ImproveRow(model: model)
                }
                if model.spec.nudge != nil { NudgeRow(model: model) }
                if catalog.folder != nil { ShareDayRow(model: model) }
                switch model.spec.view {
                case .board(let field, let expected): Board(model: model, field: field, expected: expected)
                case .timeline: ForEach(model.items) { ItemRow(model: model, item: $0, showsSpan: true) }
                case .table: Table(model: model)
                }
            }
        }
        .sheet(item: Binding(get: { actions.draft }, set: { actions.draft = $0 })) { DraftSheet(draft: $0) }
        .task(id: model.scope) { await loadMembers() }
        .onAppear(perform: model.reload)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.m) {
                Button("Read this day") { Task { await model.read() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.phase == .reading || noScreenActivity || model.isPaused)
                ReadPhaseLabel(
                    phase: model.phase, items: model.spec.itemsNoun, droppedBecause: "not backed by the source")
                Spacer()
                ViewPicker(model: model)
            }
            Text(note).textStyle(.callout).foregroundStyle(.supporting)
            if case .screen = model.source, !capture.isOn(.screen) {
                Button("Turn on Screen") { capture.set(.screen, on: true) }
                    .help("Workbench keeps which app, window and page you are in. Never pixels or keystrokes.")
            }
            if case .pages(let source) = model.source {
                HStack {
                    if !capture.isOn(.screenText) {
                        Button("Turn on Screen text") { capture.set(.screenText, on: true) }
                    }
                    Button("Change sites") { model.attempt("clear the sites") { try source.choose("") } }
                }
            }
        }
    }

    private var noScreenActivity: Bool {
        switch model.source {
        case .screen: model.sessions.isEmpty
        case .pages: model.pageReading.pages.isEmpty
        case .whatsapp: false
        }
    }

    private var note: String {
        switch model.source {
        case .whatsapp:
            return
                "Reading sends this day's messages, and the text in its photos (read on this Mac), to \(models.choice.title). Each call is on the Runs page."
        case .pages:
            let reading = model.pageReading
            guard !reading.pages.isEmpty else {
                return
                    "No page text from these sites on this day. Pages come from the Workbench browser extension while Screen text is on."
            }
            let left =
                reading.leftOut == 0 ? "" : " \(reading.leftOut) later pages are past the size limit and are left out."
            return "\(reading.pages.count) page views. Reading sends their text to \(models.choice.title).\(left)"
        case .screen:
            guard !model.sessions.isEmpty else {
                return capture.isOn(.screen)
                    ? "Screen is on. The timeline fills as you work; read the day later."
                    : "Screen is off, so there is no timeline yet. Turning it on keeps which app, window and page you are in; never pixels or keystrokes."
            }
            let minutes = model.sessions.reduce(0) { $0 + $1.minutes }
            return
                "\(model.sessions.count) windows, \(minutes / 60) h \(minutes % 60) min on screen. Reading sends their titles and addresses to \(models.choice.title); never the text on screen."
        }
    }

    private func loadMembers() async {
        guard case .whatsapp(let source) = model.source else { return }
        do {
            try await source.showMembers()
        } catch {
            model.attempt("read the group members") { throw error }
        }
    }
}

/// A new brief on trial: how it compares with the current one on past days, and the choice to switch.
private struct TrialCard: View {
    let model: HelperModel
    @Environment(Crew.self) private var crew

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Label(
                model.trial?.by == .proposer ? "Mochi proposed a change; it is on trial" : "A new version is on trial",
                systemImage: "flask"
            )
            .textStyle(.headline)
            if let why = model.trial?.why, !why.isEmpty {
                Text("Why: \(why)").textStyle(.callout)
            }
            if model.trialPhase == .reading {
                ProgressView("Reading past days with the new brief…").controlSize(.small)
            } else if let trial = model.trial {
                Text(summary(trial.result, days: trial.days.count))
                Text(verdict(trial.result)).fontWeight(.medium)
                    .foregroundStyle(
                        trial.result.verdict == .better
                            ? Tone.good.color : trial.result.verdict == .worse ? Tone.bad.color : .primary)
                Text(change(trial.version)).textStyle(.callout).foregroundStyle(.supporting).lineLimit(3)
                HStack {
                    Button("Switch to the new brief") { crew.switchToTrial(model) }
                    Button("Keep the current brief", action: model.keepCurrent)
                }
            }
        }
        .padding(Space.m)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: Radius.card))
    }

    /// What the trial changes against the live machine, in one line.
    private func change(_ version: HelperModel.Version) -> String {
        var parts: [String] = []
        if version.brief != model.spec.brief { parts.append("New brief: “\(version.brief)”") }
        if version.examples != model.spec.examples {
            parts.append(version.examples.map { "Sees \($0) of your marked examples" } ?? "No examples")
        }
        if version.runner != model.spec.runner {
            parts.append("Reads with \(version.runner.flatMap(ModelChoice.with(id:))?.title ?? "your chosen model")")
        }
        return parts.joined(separator: " · ")
    }

    private func summary(_ result: Trial, days: Int) -> String {
        "On \(days) past days: \(result.same) the same, \(result.added.count) new, \(result.dropped.count) no longer given. "
            + (result.waiting == 0 ? "" : "\(result.waiting) new ones wait for your mark in Review.")
    }

    private func verdict(_ result: Trial) -> String {
        switch result.verdict {
        case .better: "Better: right on \(result.better) of the \(result.better + result.worse) differences you marked."
        case .worse: "Worse: wrong on \(result.worse) of the \(result.better + result.worse) differences you marked."
        case .notSure:
            "Not sure yet: better on \(result.better), worse on \(result.worse) of the differences you marked. "
                + "The test stays fair however often you look; mark the waiting items in Review."
        }
    }
}

/// The proposer: Mochi reads the founder's marks on training days and puts one clear fix on trial.
private struct ImproveRow: View {
    let model: HelperModel
    @State private var asking = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.m) {
                Button(asking ? "Looking at your marks…" : "Improve from my marks") {
                    asking = true
                    Task {
                        await model.improve()
                        asking = false
                    }
                }
                .disabled(asking || model.isPaused)
                .help(
                    "Mochi reads the items you marked on training days and tries one small change on past days. You decide."
                )
                Menu("Try another model") {
                    ForEach(ModelChoice.choices.filter { $0.id != model.spec.runner }) { choice in
                        Button(choice.title) { Task { await model.tryModel(choice) } }
                    }
                }
                .fixedSize().disabled(asking || model.isPaused)
                .help("Reads your marked past days with that model and compares. The days go to that model's maker.")
                if model.spec.examples == nil {
                    Button("Learn from my marked examples") { Task { await model.learnFromMarks() } }
                        .disabled(asking || model.isPaused)
                        .help(
                            "The machine sees a few items you marked on other training days when it reads. It is tried on past days first; you decide."
                        )
                }
                if let note = model.improveNote { Text(note).textStyle(.callout).foregroundStyle(.supporting) }
            }
            History(model: model)
        }
    }
}

/// The machine's last decisions: trials, switches, rejections, rollbacks.
private struct History: View {
    let model: HelperModel

    var body: some View {
        let decisions = model.decisions.prefix(5)
        if !decisions.isEmpty {
            DisclosureGroup("History") {
                ForEach(Array(decisions.enumerated()), id: \.offset) { _, decision in
                    Text("\(decision.at.formatted(date: .abbreviated, time: .shortened)) · \(line(decision))")
                        .textStyle(.callout).foregroundStyle(.supporting)
                }
            }
            .textStyle(.callout)
        }
    }

    private func line(_ decision: Decision) -> String {
        let who = decision.by == .person ? "you" : decision.by == .proposer ? "Mochi" : "the alarm"
        switch decision.kind {
        case .trial: return "\(who) started a trial"
        case .promote: return "you switched to the new brief"
        case .reject: return "you kept the current brief"
        case .rollback:
            return
                "rolled back by the alarm (\(decision.detail["wrong"] ?? "?") of \(decision.detail["answers"] ?? "?") wrong)"
        }
    }
}

/// One line about a change the app made by itself.
private struct NoticeRow: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack {
            Label(text, systemImage: "arrow.uturn.backward.circle").foregroundStyle(Tone.attention.color)
            Button("Dismiss", action: dismiss).buttonStyle(.borderless)
        }
    }
}

/// A paused machine reads and nudges nothing until the founder resumes it.
private struct PausedNote: View {
    let model: HelperModel
    @Environment(Crew.self) private var crew

    var body: some View {
        HStack(spacing: Space.s) {
            Label("\(model.name) is paused. It reads and nudges nothing.", systemImage: "pause.circle")
            Button("Resume") { crew.setPaused(model, false) }
        }
        .foregroundStyle(Tone.attention.color)
    }
}

/// The one item the app picked from the last reading. Answering it measures the helper without your choice of what
/// to check.
private struct Question: View {
    let model: HelperModel
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Label("\(model.name) asks: is this right?", systemImage: "questionmark.bubble").textStyle(.headline)
            ItemRow(model: model, item: item, showsSpan: model.spec.citation == .range)
            Text("Picked at random from this reading, so your answer shows how often \(model.name) is right.")
                .textStyle(.callout).foregroundStyle(.supporting)
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
            .foregroundStyle(Tone.good.color).textStyle(.callout)
        case .needsMore(let more):
            Text(
                "\(name) earns trust at most 10% wrong, 90% sure. It needs at least \(more) more right answers on held-out days."
            )
            .textStyle(.callout).foregroundStyle(.supporting)
        }
    }
}

/// The sites a page machine reads. Only these sites' text is ever sent; the rest stays on the Mac.
private struct SiteChooser: View {
    let model: HelperModel
    let source: PageSource
    @State private var typed = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(
                "Name the sites \(model.name) reads, such as mail.google.com or linkedin.com. It reads only their text, only the day you ask."
            )
            .foregroundStyle(.supporting)
            HStack {
                TextField("mail.google.com, linkedin.com", text: $typed).frame(maxWidth: 360)
                Button("Use these sites") {
                    model.attempt("save the sites") { try source.choose(typed) }
                    model.reload()
                }
                .buttonStyle(.borderedProminent).disabled(typed.isEmpty)
            }
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
/// The items grouped by person: everyone with items first, then one line naming everyone the day has none from.
private struct Board: View {
    let model: HelperModel
    let field: String
    let expected: String

    var body: some View {
        if !silent.isEmpty {
            Label(
                "No \(model.spec.itemsNoun) from \(silent.joined(separator: ", "))", systemImage: "questionmark.circle"
            )
            .foregroundStyle(Tone.attention.color)
        }
        ForEach(groups, id: \.self) { group in
            VStack(alignment: .leading, spacing: Space.s) {
                Text(group).textStyle(.headline)
                ForEach(model.items.filter { $0[field] == group }) { ItemRow(model: model, item: $0, showsSpan: false) }
            }
            Divider()
        }
    }

    /// People with items: expected names in their order, then any other name an item gives.
    private var groups: [String] {
        let named = Set(model.items.map { $0[field] })
        let names = model.context[expected] ?? []
        return names.filter(named.contains) + named.subtracting(names).sorted()
    }

    private var silent: [String] {
        let named = Set(model.items.map { $0[field] })
        return (model.context[expected] ?? []).filter { !named.contains($0) }
    }
}

/// The views this machine's spec can fill, as a switch. Hidden when there is only one.
private struct ViewPicker: View {
    let model: HelperModel
    @Environment(Crew.self) private var crew

    var body: some View {
        let views = model.spec.views
        if views.count > 1 {
            Picker("View", selection: Binding(get: { current(in: views) }, set: { crew.show(model, as: $0) })) {
                ForEach(views.keys.sorted(), id: \.self) { Text($0.capitalized).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
        }
    }

    private func current(in views: [String: HelperSpec.View]) -> String {
        views.first { $0.value == model.spec.view }?.key ?? "table"
    }
}

/// One row per item: a column per field, then the quote it came from and the marks.
private struct Table: View {
    let model: HelperModel

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: Space.m, verticalSpacing: Space.s) {
            GridRow {
                ForEach(model.spec.fields, id: \.name) { Text($0.name.capitalized) }
                Text("Quote")
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
            .textStyle(.caption).foregroundStyle(.supporting)
            Divider()
            ForEach(model.items) { item in
                GridRow {
                    ForEach(model.spec.fields, id: \.name) { Text(item[$0.name]) }
                    Text("“\(item.quote)”").textStyle(.callout).foregroundStyle(.supporting).textSelection(.enabled)
                    HStack(spacing: Space.s) {
                        MarkButtons(state: item.state) { model.mark(item, as: $0) }
                        ItemActions(model: model, item: item)
                    }
                }
                .opacity(item.state == .rejected ? 0.5 : 1)
            }
        }
    }
}

private struct ItemRow: View {
    let model: HelperModel
    let item: Item
    let showsSpan: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            if showsSpan {
                Text(span).textStyle(.callout, digits: true).foregroundStyle(.supporting)
                    .frame(width: 110, alignment: .leading)
            } else if let (value, tone) = toned {
                Image(systemName: tone.symbol).foregroundStyle(tone.color).frame(width: 18).accessibilityLabel(value)
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.s) {
                    Text(item[model.spec.title])
                    ForEach(model.spec.badges.map { item[$0] }.filter { !$0.isEmpty }, id: \.self) { badge in
                        Text(badge).textStyle(.caption).padding(.horizontal, Space.s).padding(.vertical, 2)
                            .background(.quaternary, in: .capsule)
                    }
                }
                Text(showsSpan ? "“\(item.quote)”" : "“\(item.quote)” · \(time(item.start))")
                    .textStyle(.callout).foregroundStyle(.supporting).textSelection(.enabled)
            }
            .opacity(item.state == .rejected ? 0.5 : 1)
            .strikethrough(item.state == .rejected)
            Spacer()
            MarkButtons(state: item.state) { model.mark(item, as: $0) }
            ItemActions(model: model, item: item)
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

/// Shares the shown day's items with the team: only the items, their quotes and the founder's marks, and only to
/// teammates who can already read the source.
private struct ShareDayRow: View {
    let model: HelperModel
    @Environment(TeamCatalogModel.self) private var catalog

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.m) {
                if catalog.isShared(day: model) {
                    Label("Shared with your team", systemImage: "person.2.fill").foregroundStyle(Tone.good.color)
                    Button("Update") { Task { await catalog.share(day: model) } }
                    Button("Stop sharing") { catalog.unshare(day: model) }
                } else {
                    Button("Share this day with the team") { Task { await catalog.share(day: model) } }
                        .disabled(model.items.isEmpty)
                        .help(
                            "Shares the items, their quotes and your marks; never the other messages or windows. Only to teammates who can already read the source."
                        )
                }
            }
            if let refusal = catalog.refusal, refusal.task == model.spec.task {
                RefusalCard(model: model, refusal: refusal)
            }
        }
    }
}

/// Why a share was held back, and for a group, a way to say who each teammate is in it.
private struct RefusalCard: View {
    let model: HelperModel
    let refusal: TeamCatalogModel.Refusal
    @Environment(TeamCatalogModel.self) private var catalog

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Label("Not shared", systemImage: "hand.raised").textStyle(.headline)
            if refusal.group.isEmpty {
                Text(
                    "These items come from your screen, which only you can see. Window titles can name other people's mail and chats, so they stay on your Mac."
                )
            } else {
                Text(
                    "Workbench shares a group's items only with teammates who are in that group. Say who each one is in it, then choose Share again."
                )
                ForEach(refusal.missing) { person in
                    Menu("Who is \(person.name) in the group?") {
                        ForEach(refusal.group, id: \.jid) { member in
                            Button(member.name) { Task { await catalog.link(person, to: member, for: model) } }
                        }
                    }
                    .fixedSize()
                }
                Text("A teammate who is not in the group cannot receive its items.").textStyle(.callout)
                    .foregroundStyle(.supporting)
            }
            Button("Dismiss", action: catalog.dismissRefusal)
        }
        .padding(Space.m)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: Radius.card))
    }
}

/// What the founder can do with one item. Each choice is the founder's click; nothing is sent.
private struct ItemActions: View {
    let model: HelperModel
    let item: Item
    @Environment(ActionsModel.self) private var actions
    @Environment(DealsModel.self) private var deals

    var body: some View {
        if actions.drafting == item.id {
            ProgressView().controlSize(.small)
        } else {
            Menu("Act on this", systemImage: "ellipsis.circle") {
                Button("Draft a message…") { Task { await actions.draft(item, from: model.machine) } }
                Button("Add to Reminders") {
                    Task { await actions.remind(item, from: model.machine, title: item[model.spec.title]) }
                }
                Divider()
                Button("New deal from this item") { Task { await deals.newDeal(from: item, of: model) } }
                if !deals.deals.isEmpty {
                    Menu("Add to a deal") {
                        ForEach(deals.deals) { deal in
                            Button(deal.title) { Task { await deals.link(item, from: model, to: deal.id) } }
                        }
                    }
                }
            }
            .labelStyle(.iconOnly).menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .disabled(item.state == .rejected)
        }
    }
}

/// The drafted message, editable. Copy is the only way out; the founder sends it themselves.
private struct DraftSheet: View {
    @State var draft: ActionsModel.Draft
    @Environment(ActionsModel.self) private var actions
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(draft.to.isEmpty ? "Draft" : "Draft for \(draft.to)").textStyle(.headline)
            TextEditor(text: $draft.text).frame(minWidth: 420, minHeight: 140).textStyle(.body)
            Text("Workbench never sends it. Copy it, then paste it where you send it.").textStyle(.callout)
                .foregroundStyle(.supporting)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Copy") { actions.copy(draft) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.l)
    }
}

/// The result of the last act, or why it could not happen.
private struct ActionNotice: View {
    @Environment(ActionsModel.self) private var actions

    var body: some View {
        if let problem = actions.problem {
            ProblemBanner(text: problem, dismiss: actions.dismiss)
        } else if actions.remindersBlocked {
            HStack {
                Text("Reminders is off for Workbench. Turn it on in System Settings, then try again.")
                Button("Open Settings", action: AppleReminders.openSettings)
                Button("Dismiss", action: actions.dismiss)
            }
        } else if let notice = actions.notice {
            HStack {
                Label(notice, systemImage: "checkmark.circle").foregroundStyle(Tone.good.color)
                Button("Dismiss", action: actions.dismiss).buttonStyle(.borderless)
            }
        }
    }
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
            .textStyle(.callout).foregroundStyle(.supporting)
            if model.notificationsBlocked {
                HStack(spacing: Space.s) {
                    Label("macOS blocks Workbench notifications.", systemImage: "bell.slash")
                        .foregroundStyle(Tone.attention.color)
                    Button("Allow in System Settings", action: SystemNotifier.openSettings)
                }
                .textStyle(.callout)
            }
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
