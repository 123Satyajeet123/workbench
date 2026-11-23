import Foundation
import LocalSources
import Observation
import WorkbenchCore

enum FactChoice: Equatable {
    case done, notRelevant, wrong
    case snooze(until: WorkDay)
    case handOff(to: String)
}

struct ChatLine: Identifiable, Equatable {
    var id: Int64
    var time: Date?
    var text: String
    var isCited: Bool

    /// The lines an item cites and `reach` lines before and after each.
    static func around(_ item: Item, in lines: [Evidence], reach: Int64) -> [ChatLine] {
        let cited = item.citeFirst...item.citeLast
        return lines.filter { ($0.id - reach...$0.id + reach).overlaps(cited) }.map {
            ChatLine(id: $0.id, time: $0.start, text: $0.line, isCited: cited.contains($0.id))
        }
    }
}

struct SummaryRow: Identifiable {
    var summary: Summary
    var line: Summary.Line
    var facts: [Item]
    var openCount: Int

    var id: String { summary.scope }
    var subject: String { summary.subject }
}

/// What Today, People and Projects show: the facts of the last seven days, the day's summaries, and the morning list:
/// what the founder owes, what slipped, what waits on whom. It reads the store; the one model call it may start is the day's missing summaries. An action is a mark
/// or an event, and can be taken back.
@Observable
final class TodayModel {
    private static let firstRunKey = StateKey<String>.text("morning.firstrun")

    static let days = 7

    struct Undo: Equatable {
        var plan: [ItemAction: [Int64]]
        var text: String
    }

    private(set) var today: WorkDay
    private(set) var sections: [MorningSection] = []
    /// The open facts older than the cutoff that the first morning list offers to mark as handled; empty once the
    /// person answered the offer.
    private(set) var backlog: [Item] = []
    private(set) var team: [SummaryRow] = []
    /// Today's facts of the people with no summary line, so a day with facts never looks empty.
    private(set) var unsummarized: [FactGroup] = []
    private(set) var isSummarizing = false
    private(set) var projects: [SummaryRow] = []
    private(set) var people: [FactGroup] = []
    private(set) var projectGroups: [FactGroup] = []
    private(set) var meetingCards: [MeetingCard] = []
    /// For each revisit on Today, the news about its company since the investor passed.
    private(set) var passedNews: [Int64: [Item]] = [:]
    private(set) var undoable: Undo?
    /// The bulk "handled" the person just made, which one click takes back.
    private(set) var handledBatch: HandledBatch?
    private(set) var problem: String?
    /// Counts each load, so a view can animate what changed between two loads.
    private(set) var revision = 0

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let crew: Crew
    @ObservationIgnored private let deals: () -> [WorkObject]
    @ObservationIgnored private let me: () -> String
    @ObservationIgnored let meetings: MeetingsModel
    @ObservationIgnored private var daysAsked: Set<WorkDay> = []

    /// With no `calendar`, Today shows no meetings and never offers them.
    init(
        store: Store, crew: Crew, calendar: (any CalendarEvents)? = nil, deals: @escaping () -> [WorkObject] = { [] },
        me: @escaping () -> String = { "" }, defaults: UserDefaults = .standard
    ) {
        self.store = store
        self.crew = crew
        self.deals = deals
        self.me = me
        meetings = MeetingsModel(store: store, calendar: calendar, defaults: defaults)
        today = WorkDay(containing: store.clock())
        refresh()
        crew.onItemsChanged { [weak self] in self?.refresh() }
    }

    /// The lines that ask the founder to do something: every section except "Owed to you" and "Waiting on others".
    var needs: [Need] { sections.filter(\.kind.needsPerson).flatMap(\.lines) }

    /// What Today's badge and the morning notification count.
    var needsCount: Int { MorningList.needsCount(sections) }

    /// Whether the first morning list offers to mark the old backlog as handled.
    var offersCutoff: Bool { !backlog.isEmpty }

    /// N of the first-run cutoff: the person's setting.
    var cutoffDays: Int {
        ((try? MorningSchedule.settingsKey.load(from: store)) ?? nil)?.cutoffDays ?? FirstRun.defaultDays
    }

    var isEmpty: Bool {
        sections.isEmpty && team.isEmpty && unsummarized.isEmpty && projects.isEmpty && meetingCards.isEmpty
    }

    private var factHelper: HelperModel? { crew.team }
    private var factMachine: Machine? { factHelper?.machine }
    private var sentinelTask: String? {
        crew.machines.first { $0.machine.template == HelperSpec.derailment.task }?.spec.task
    }

    func refresh() {
        do {
            try load()
            problem = nil
        } catch {
            problem = "Could not read your day: \(error.localizedDescription)"
        }
        revision += 1
    }

    /// Reads today's meetings when the calendar consent is on, then matches them to what Today knows.
    func refreshMeetings() async {
        await meetings.refresh()
        buildMeetingCards()
        revision += 1
    }

    private func buildMeetingCards() {
        meetingCards = MeetingPrep.cards(
            for: meetings.meetings, groups: people, rows: team, deals: deals(),
            actions: (try? store.queries.openDealActions()) ?? [], now: store.clock())
    }

    private func load() throws {
        let now = store.clock()
        today = WorkDay(containing: now)
        let dealActions = try store.queries.openDealActions()
        let revisits = try store.queries.openRevisits()
        let news = try store.queries.newsSignals(since: today.adding(days: 1 - Store.newsRetentionDays))
        passedNews = try passedNews(of: revisits, now: now)
        var input = MorningInput(facts: dealActions, me: me())
        input.revisits = revisits
        input.news = news
        input.firedTimers = try store.queries.itemsWithFiredTimers()
        guard let machine = factMachine else {
            clear()
            sections = MorningList.pick(input, now: now)
            buildMeetingCards()
            return
        }
        let lifecycle = machine.spec.lifecycleOrNone
        let open = try store.queries.openItems(of: machine.task, lifecycle: lifecycle)
        let facts = try recentFacts(of: machine, open: open, since: today.adding(days: 1 - Self.days))
        let listed = facts.filter { $0.isListed(at: now) }
        input.facts += open
        input.findings = try sentinelTask.map { try store.queries.items(of: $0, on: today) } ?? []
        input.ownerField = lifecycle.owner ?? input.ownerField
        input.askerField = lifecycle.asker
        sections = MorningList.pick(input, now: now)
        backlog = try cutoffOffer(open)
        people = group(facts, by: machine.spec.memberField, lifecycle, now)
        projectGroups = group(facts, by: machine.spec.labelField, lifecycle, now)
        team = try rows(
            machine.spec.memberField, of: machine, day: today, listed: listed, groups: people, countsOpen: false)
        unsummarized = withoutSummary(facts.filter { $0.day == today }, machine, lifecycle, now)
        projects = try rows(
            machine.spec.labelField, of: machine, day: today, listed: listed, groups: projectGroups, countsOpen: true)
        buildMeetingCards()
    }

    /// The open facts the first list offers to mark as handled: none once the person answered the offer.
    private func cutoffOffer(_ open: [Item]) throws -> [Item] {
        guard try Self.firstRunKey.load(from: store) == nil else { return [] }
        return FirstRun.older(open, thanDays: cutoffDays, today: today)
    }

    /// The listed news about each revisit's company from the day of the pass on.
    private func passedNews(of revisits: [Item], now: Date) throws -> [Int64: [Item]] {
        var found: [Int64: [Item]] = [:]
        for revisit in revisits {
            guard let id = revisit.id else { continue }
            found[id] = try store.queries.newsSignals(of: revisit[Revisit.dealField], since: revisit.day)
                .filter { $0.isListed(at: now) }
        }
        return found
    }

    private func clear() {
        sections = []
        backlog = []
        team = []
        unsummarized = []
        projects = []
        people = []
        projectGroups = []
    }

    /// The facts of the window and every fact still open, however old.
    private func recentFacts(of machine: Machine, open: [Item], since day: WorkDay) throws -> [Item] {
        let recent = try store.queries.items(of: machine.task, since: day)
        let known = Set(recent.compactMap(\.id))
        return recent + open.filter { $0.id.map { !known.contains($0) } ?? false }
    }

    private func group(_ facts: [Item], by field: String?, _ lifecycle: HelperSpec.Lifecycle, _ now: Date)
        -> [FactGroup]
    {
        field.map { FactGroups.make(facts, by: $0, lifecycle: lifecycle, now: now) } ?? []
    }

    private func rows(
        _ field: String?, of machine: Machine, day: WorkDay, listed: [Item], groups: [FactGroup], countsOpen: Bool
    ) throws -> [SummaryRow] {
        guard let field else { return [] }
        let byID = Dictionary(listed.compactMap { item in item.id.map { ($0, item) } }, uniquingKeysWith: { a, _ in a })
        return try store.queries.summaries(day: day, task: machine.task, field: field).compactMap { summary in
            guard let line = summary.short, line.isShown(among: Set(byID.keys)) else { return nil }
            let open = countsOpen ? groups.first { $0.name == summary.subject }?.open.count ?? 0 : 0
            return SummaryRow(summary: summary, line: line, facts: line.cites.compactMap { byID[$0] }, openCount: open)
        }
    }

    private func withoutSummary(_ facts: [Item], _ machine: Machine, _ lifecycle: HelperSpec.Lifecycle, _ now: Date)
        -> [FactGroup]
    {
        guard let field = machine.spec.memberField else { return [] }
        return FactGroups.unsummarized(
            facts, by: field, lifecycle: lifecycle, summarized: Set(team.map(\.subject)), now: now)
    }

    /// Writes today's summaries when the fact machine has facts for today that lack them. Asks at most once for each
    /// day, so a failing model is not retried at every visit. A reading writes its own summaries.
    func summarizeIfMissing() async {
        guard !isSummarizing, !daysAsked.contains(today), let helper = factHelper, !helper.isPaused,
            helper.hasMissingSummaries(on: today)
        else { return }
        daysAsked.insert(today)
        isSummarizing = true
        let isCurrent = await helper.summarize(today)
        isSummarizing = false
        refresh()
        if !isCurrent { problem = "Could not summarize your day. Its facts are listed without a summary." }
    }

    func perform(_ choice: FactChoice, on items: [Item], text: String) {
        let plan = plan(for: choice, items)
        guard !plan.isEmpty else { return }
        do {
            try store.apply(plan, surface: .today)
            undoable = Undo(plan: plan, text: text)
            reloadMachines()
        } catch {
            problem = "Could not save that: \(error.localizedDescription)"
            refresh()
        }
    }

    func undo() {
        guard let undoable else { return }
        do {
            try store.undo(undoable.plan, surface: .today)
            self.undoable = nil
            reloadMachines()
        } catch {
            problem = "Could not take that back: \(error.localizedDescription)"
            refresh()
        }
    }

    func title(of item: Item) -> String {
        if NewsSignals.owns(item.task) { return item[NewsSignals.headlineField] }
        let field = crew.machines.first { $0.spec.task == item.task }?.spec.title
        return field.map { item[$0] } ?? item.quote
    }

    /// The count of open facts a group shows beside its name, or nil for none. A person's own count is shown to that
    /// person only: the group of another person shows no count, so a page never ranks people.
    func shownOpenCount(of group: FactGroup, lens: FactGroupsPage.Lens) -> Int? {
        guard !group.open.isEmpty else { return nil }
        switch lens {
        case .projects: return group.open.count
        case .people: return group.name.caseInsensitiveCompare(me()) == .orderedSame ? group.open.count : nil
        }
    }

    /// The people a fact may be handed to: the other people the facts name, by name.
    var handOffPeople: [String] {
        people.map(\.name).filter { !$0.isEmpty && $0.caseInsensitiveCompare(me()) != .orderedSame }
    }

    /// Marks the backlog as handled in one bulk event, and keeps the offer from coming back.
    func markBacklogHandled() {
        do {
            let ids = backlog.compactMap(\.id)
            let batch = try store.markHandled(
                ids, olderThanDays: cutoffDays, cutoff: today.adding(days: -cutoffDays), surface: .today)
            try Self.firstRunKey.save("handled", to: store)
            handledBatch = batch
            reloadMachines()
        } catch {
            problem = "Could not mark them as handled: \(error.localizedDescription)"
            refresh()
        }
    }

    /// Takes the bulk "handled" back: each fact it closed is reopened.
    func reopenHandled() {
        guard let batch = handledBatch else { return }
        do {
            try store.reopenHandled(batch: batch.id, surface: .today)
            handledBatch = nil
            reloadMachines()
        } catch {
            problem = "Could not reopen them: \(error.localizedDescription)"
            refresh()
        }
    }

    /// The person keeps the backlog as it is.
    func keepBacklog() {
        do {
            try Self.firstRunKey.save("kept", to: store)
            refresh()
        } catch {
            problem = "Could not save that: \(error.localizedDescription)"
        }
    }

    func dismissUndo() { undoable = nil }
    func dismissProblem() { problem = nil }

    private func plan(for choice: FactChoice, _ items: [Item]) -> [ItemAction: [Int64]] {
        let ids = items.compactMap(\.id)
        switch choice {
        case .notRelevant: return ids.isEmpty ? [:] : [.notRelevant: ids]
        case .wrong: return ids.isEmpty ? [:] : [.wrong: ids]
        case .snooze(let day): return ids.isEmpty ? [:] : [.snooze(until: day): ids]
        case .handOff(let person):
            let name = person.trimmingCharacters(in: .whitespaces)
            return ids.isEmpty || name.isEmpty ? [:] : [.handOff(to: name): ids]
        case .done: return closing(items)
        }
    }

    /// A fact closes with its lifecycle's outcome, a deal's action as done; a finding, which has no lifecycle, is
    /// handled.
    private func closing(_ items: [Item]) -> [ItemAction: [Int64]] {
        let task = factMachine?.task
        var plan = factMachine?.spec.lifecycle?.closing(items.filter { $0.task == task }) ?? [:]
        plan.merge(DealAction.lifecycle.closing(items.filter { $0.task == DealAction.task })) { $0 + $1 }
        plan.merge(Revisit.lifecycle.closing(items.filter { $0.task == Revisit.task })) { $0 + $1 }
        let own = [task, DealAction.task, Revisit.task]
        let findings = items.filter { !own.contains($0.task) && $0.closed == nil }.compactMap(\.id)
        if !findings.isEmpty { plan[.done(outcome: "handled")] = findings }
        return plan
    }

    /// The chat lines around the ones a fact cites. A WhatsApp fact shows the lines its run read, from the evidence
    /// store: the chat is not read again, and a message deleted since shows as deleted. Another source gives its lines as
    /// it has them now. Empty when the fact cites no line or its machine is gone.
    func chatLines(around item: Item, reach: Int = 2) async throws -> [ChatLine] {
        guard item.citeFirst > 0, let helper = crew.machines.first(where: { $0.spec.task == item.task }) else {
            return []
        }
        if let whatsApp = helper.source as? WhatsAppSource { return try await whatsApp.proof(of: item, reach: reach) }
        return ChatLine.around(item, in: try await helper.source.evidence(on: item.day).lines, reach: Int64(reach))
    }

    private func reloadMachines() {
        for helper in crew.machines { helper.reload() }
        crew.machines.first?.itemsChanged()
    }
}
