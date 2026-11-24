import Foundation
import LocalSources
import Observation
import WorkbenchCore

enum FactChoice: Equatable {
    case done, right, notRelevant, wrong
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
    /// The value the summary groups by, as the roster names it: a member by plain name.
    var subject: String

    var id: String { summary.scope }
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
    /// The follow-ups of the last calls: those still open, and those done in the window.
    private(set) var callFollowUps: [Item] = []
    private(set) var undoable: Undo?
    /// The bulk "handled" the person just made, which one click takes back.
    private(set) var handledBatch: HandledBatch?
    let problems = ProblemSlot()
    var problem: String? { problems.text }
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
        ((try? MorningSchedule.settingsKey.load(from: store)) ?? nil)?.cutoffDays
            ?? RunSettings.standard.backlogCutoffDays
    }

    var isEmpty: Bool {
        sections.isEmpty && team.isEmpty && unsummarized.isEmpty && projects.isEmpty && meetingCards.isEmpty
            && callFollowUps.isEmpty
    }

    /// The lifecycle of each fact Today lists, by task: each fact keeper's own, and the store's typed facts.
    private var lifecycles: [String: HelperSpec.Lifecycle] {
        HelperSpec.Lifecycle.ofFactsWithoutMachine.merging(
            crew.factKeepers.compactMap { helper in helper.spec.lifecycle.map { (helper.spec.task, $0) } }
        ) { typed, _ in typed }
    }

    func refresh() {
        problems.attempt("read your day", clearing: true) { try load() }
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
            actions: (try? store.queries.openDealActions().items) ?? [], now: store.clock())
    }

    private func load() throws {
        let now = store.clock()
        today = WorkDay(containing: now)
        let keepers = crew.factKeepers.map(\.machine)
        let lifecycles = self.lifecycles
        let specs = Dictionary(keepers.map { ($0.task, $0.spec) }) { first, _ in first }
        let revisits = try store.queries.openRevisits().items
        passedNews = try passedNews(of: revisits, now: now)
        let open = try keepers.flatMap { try store.queries.openItems(readBy: $0.spec) }
        let openFromCalls = try HelperSpec.withoutMachine.flatMap { try store.queries.openItems(readBy: $0.spec) }
        var input = MorningInput(facts: try store.queries.openDealActions().items + openFromCalls + open, me: me())
        input.revisits = revisits
        input.news = try store.queries.newsSignals(
            since: today.adding(days: 1 - RunSettings.standard.newsRetentionDays))
        input.firedTimers = try store.queries.itemsWithFiredTimers()
        input.findings = try crew.factReaders.flatMap { try store.queries.items(of: $0.spec.task, on: today) }
        input.ownerField = { lifecycles[$0.task]?.owner }
        input.askerField = { lifecycles[$0.task]?.asker }
        sections = MorningList.pick(input, now: now)
        backlog = try cutoffOffer(open)
        let since = today.adding(days: 1 - Self.days)
        callFollowUps = try recentCallFollowUps(open: openFromCalls, since: since, now: now)
        let facts = try keepers.flatMap { machine in
            try recentFacts(of: machine, open: open.filter { $0.task == machine.task }, since: since)
        }
        let listed = facts.filter { $0.isListed(at: now) }
        let lifecycle = { (fact: Item) in lifecycles[fact.task] }
        let member = { (fact: Item) in specs[fact.task]?.memberField }
        let label = { (fact: Item) in specs[fact.task]?.labelField }
        let roster = MemberRoster(names: [me()], founder: me())
        people = FactGroups.make(facts, by: member, roster: roster, lifecycle: lifecycle, now: now)
        projectGroups = FactGroups.make(facts, by: label, lifecycle: lifecycle, now: now)
        team = try keepers.flatMap {
            try rows(
                $0.spec.memberField, of: $0, day: today, listed: listed, groups: people, roster: roster,
                countsOpen: false)
        }
        unsummarized = FactGroups.unsummarized(
            facts.filter { $0.day == today }, by: member, roster: roster, lifecycle: lifecycle,
            summarized: Set(team.map(\.subject)), now: now)
        projects = try keepers.flatMap {
            try rows(
                $0.spec.labelField, of: $0, day: today, listed: listed, groups: projectGroups, roster: .none,
                countsOpen: true)
        }
        buildMeetingCards()
    }

    /// The follow-ups of calls from the window, and every one still open, however old; one dropped is left out.
    private func recentCallFollowUps(open: [Item], since day: WorkDay, now: Date) throws -> [Item] {
        let recent = try HelperSpec.withoutMachine.flatMap { try store.queries.items(of: $0.spec.task, since: day) }
        let known = Set(recent.compactMap(\.id))
        return (open.filter { $0.id.map { !known.contains($0) } ?? false } + recent).filter { item in
            item.isListed(at: now) && (item.closed == nil || item.closed?.outcome == "done")
        }
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
            found[id] = try store.queries.newsSignals(of: revisit[.deal], since: revisit.day)
                .filter { $0.isListed(at: now) }
        }
        return found
    }

    /// The facts of the window and every fact still open, however old.
    private func recentFacts(of machine: Machine, open: [Item], since day: WorkDay) throws -> [Item] {
        let recent = try store.queries.items(of: machine.task, since: day)
        let known = Set(recent.compactMap(\.id))
        return recent + open.filter { $0.id.map { !known.contains($0) } ?? false }
    }

    private func rows(
        _ field: String?, of machine: Machine, day: WorkDay, listed: [Item], groups: [FactGroup], roster: MemberRoster,
        countsOpen: Bool
    ) throws -> [SummaryRow] {
        guard let field else { return [] }
        let byID = Dictionary(listed.compactMap { item in item.id.map { ($0, item) } }, uniquingKeysWith: { a, _ in a })
        return try store.queries.summaries(day: day, task: machine.task, field: field).compactMap { summary in
            guard let line = summary.short, line.isShown(among: Set(byID.keys)) else { return nil }
            let subject = roster.canonical(summary.subject)
            let open = countsOpen ? groups.first { $0.name == subject }?.open.count ?? 0 : 0
            return SummaryRow(
                summary: summary, line: line, facts: line.cites.compactMap { byID[$0] }, openCount: open,
                subject: subject)
        }
    }

    /// Writes today's summaries when the fact machine has facts for today that lack them. Asks at most once for each
    /// day, so a failing model is not retried at every visit. A reading writes its own summaries.
    func summarizeIfMissing() async {
        let missing = crew.factKeepers.filter { !$0.isPaused && $0.hasMissingSummaries(on: today) }
        guard !isSummarizing, !daysAsked.contains(today), !missing.isEmpty else { return }
        daysAsked.insert(today)
        isSummarizing = true
        var isCurrent = true
        for helper in missing where !(await helper.summarize(today)) { isCurrent = false }
        isSummarizing = false
        refresh()
        if !isCurrent { problems.show("Could not summarize your day. Its facts are listed without a summary.") }
    }

    func perform(_ choice: FactChoice, on items: [Item], text: String) {
        if choice == .right {
            problems.attempt("save that", clearing: true) {
                for id in items.compactMap(\.id) { try store.mark(item: id, as: .confirmed) }
            }
            reloadMachines()
            return
        }
        let plan = plan(for: choice, items)
        guard !plan.isEmpty else { return }
        do {
            try store.apply(plan, surface: .today)
            undoable = Undo(plan: plan, text: text)
            reloadMachines()
        } catch {
            refresh()
            problems.report("save that", error)
        }
    }

    func undo() {
        guard let undoable else { return }
        do {
            try store.undo(undoable.plan, surface: .today)
            self.undoable = nil
            reloadMachines()
        } catch {
            refresh()
            problems.report("take that back", error)
        }
    }

    func isClosable(_ item: Item) -> Bool {
        guard let lifecycle = lifecycles[item.task] else { return true }
        return lifecycle.open.contains(item[lifecycle.field])
    }

    func isDone(_ items: [Item]) -> Bool {
        let closable = items.filter(isClosable)
        return !closable.isEmpty && closable.allSatisfy { $0.closed != nil }
    }

    func reopen(_ items: [Item]) {
        let ids = items.filter { $0.closed != nil }.compactMap(\.id)
        guard !ids.isEmpty else { return }
        do {
            for id in ids { try store.reopen(item: id, surface: .today) }
            undoable = nil
            reloadMachines()
        } catch {
            refresh()
            problems.report("reopen that", error)
        }
    }

    func title(of item: Item) -> String {
        if NewsSignals.owns(item.task) { return item[NewsSignals.headlineField] }
        let field = crew.spec(ofTask: item.task)?.title
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
            problems.report("mark them as handled", error)
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
            problems.report("reopen them", error)
            refresh()
        }
    }

    /// The person keeps the backlog as it is.
    func keepBacklog() {
        do {
            try Self.firstRunKey.save("kept", to: store)
            refresh()
        } catch {
            problems.report("save that", error)
        }
    }

    func dismissUndo() { undoable = nil }

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
        case .right: return [:]
        }
    }

    /// A fact closes with its own lifecycle's outcome; a finding, which has no lifecycle, is handled.
    private func closing(_ items: [Item]) -> [ItemAction: [Int64]] {
        let lifecycles = self.lifecycles
        var plan: [ItemAction: [Int64]] = [:]
        var findings: [Int64] = []
        for (task, items) in Dictionary(grouping: items, by: \.task) {
            if let lifecycle = lifecycles[task] {
                plan.merge(lifecycle.closing(items)) { $0 + $1 }
            } else {
                findings += items.filter { $0.closed == nil }.compactMap(\.id)
            }
        }
        if !findings.isEmpty { plan[.done(outcome: "handled")] = findings }
        return plan
    }

    /// The chat lines around the ones a fact cites. A WhatsApp fact shows the lines its run read, from the evidence
    /// store: the chat is not read again, and a message deleted since shows as deleted. Another source gives its lines as
    /// it has them now. Empty when the fact cites no line or its machine is gone.
    func chatLines(around item: Item, reach: Int = 2) async throws -> [ChatLine] {
        guard item.citeFirst > 0, let helper = crew.helper(task: item.task) else {
            return []
        }
        return try await helper.source.proof(of: item, reach: reach)
    }

    private func reloadMachines() {
        for helper in crew.machines { helper.reload() }
        crew.machines.first?.itemsChanged()
    }
}
