import Foundation
import LocalSources
import Observation
import WorkbenchCore

enum FactChoice: Equatable {
    case done, notRelevant, wrong
    case snooze(until: WorkDay)
}

struct ChatLine: Identifiable, Equatable {
    var id: Int64
    var time: Date
    var text: String
    var isCited: Bool

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

@Observable
final class TodayModel {
    static let days = 7

    struct Undo: Equatable {
        var plan: [ItemAction: [Int64]]
        var text: String
    }

    private(set) var today: WorkDay
    private(set) var needs: [Need] = []
    private(set) var team: [SummaryRow] = []
    private(set) var unsummarized: [FactGroup] = []
    private(set) var isSummarizing = false
    private(set) var projects: [SummaryRow] = []
    private(set) var people: [FactGroup] = []
    private(set) var projectGroups: [FactGroup] = []
    private(set) var meetingCards: [MeetingCard] = []
    private(set) var undoable: Undo?
    let problems = ProblemSlot()
    var problem: String? { problems.text }
    private(set) var revision = 0

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let crew: Crew
    @ObservationIgnored private let deals: () -> [WorkObject]
    @ObservationIgnored let meetings: MeetingsModel
    @ObservationIgnored private var daysAsked: Set<WorkDay> = []

    init(
        store: Store, crew: Crew, calendar: (any CalendarEvents)? = nil, deals: @escaping () -> [WorkObject] = { [] },
        defaults: UserDefaults = .standard
    ) {
        self.store = store
        self.crew = crew
        self.deals = deals
        meetings = MeetingsModel(store: store, calendar: calendar, defaults: defaults)
        today = WorkDay(containing: store.clock())
        refresh()
        crew.onItemsChanged { [weak self] in self?.refresh() }
    }

    var isEmpty: Bool {
        needs.isEmpty && team.isEmpty && unsummarized.isEmpty && projects.isEmpty && meetingCards.isEmpty
    }

    private var factMachines: [Machine] { crew.factKeepers.map(\.machine) }
    private var sentinelTask: String? {
        crew.sentinel?.spec.task
    }

    func refresh() {
        problems.attempt("read your day", clearing: true) { try load() }
        revision += 1
    }

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
        guard let machine = factMachines.first else {
            clear()
            needs = Needs.pick(facts: dealActions, findings: [], today: today, now: now)
            buildMeetingCards()
            return
        }
        let lifecycle = machine.spec.lifecycleOrNone
        let since = today.adding(days: 1 - Self.days)
        let facts = try factMachines.flatMap { try recentFacts(of: $0, lifecycle: lifecycle, since: since) }
        let findings = try sentinelTask.map { try store.queries.items(of: $0, on: today) } ?? []
        let listed = facts.filter { $0.isListed(at: now) }
        needs = Needs.pick(facts: facts + dealActions, findings: findings, today: today, now: now)
        people = group(facts, by: machine.spec.memberField, lifecycle, now)
        projectGroups = group(facts, by: machine.spec.labelField, lifecycle, now)
        team = try factMachines.flatMap {
            try rows(machine.spec.memberField, of: $0, day: today, listed: listed, groups: people)
        }
        unsummarized = withoutSummary(facts.filter { $0.day == today }, machine, lifecycle, now)
        projects = try factMachines.flatMap {
            try rows(machine.spec.labelField, of: $0, day: today, listed: listed, groups: projectGroups)
        }
        buildMeetingCards()
    }

    private func clear() {
        needs = []
        team = []
        unsummarized = []
        projects = []
        people = []
        projectGroups = []
    }

    private func recentFacts(of machine: Machine, lifecycle: HelperSpec.Lifecycle, since day: WorkDay) throws -> [Item]
    {
        let recent = try store.queries.items(of: machine.task, since: day)
        let open = try store.queries.openItems(of: machine.task, lifecycle: lifecycle)
        let known = Set(recent.compactMap(\.id))
        return recent + open.filter { $0.id.map { !known.contains($0) } ?? false }
    }

    private func group(_ facts: [Item], by field: String?, _ lifecycle: HelperSpec.Lifecycle, _ now: Date)
        -> [FactGroup]
    {
        field.map { FactGroups.make(facts, by: $0, lifecycle: lifecycle, now: now) } ?? []
    }

    private func rows(
        _ field: String?, of machine: Machine, day: WorkDay, listed: [Item], groups: [FactGroup]
    ) throws -> [SummaryRow] {
        guard let field else { return [] }
        let byID = Dictionary(listed.compactMap { item in item.id.map { ($0, item) } }, uniquingKeysWith: { a, _ in a })
        return try store.queries.summaries(day: day, task: machine.task, field: field).compactMap { summary in
            guard let line = summary.short, line.isShown(among: Set(byID.keys)) else { return nil }
            let open = groups.first { $0.name == summary.subject }?.open.count ?? 0
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
        let plan = plan(for: choice, items)
        guard !plan.isEmpty else { return }
        do {
            try store.apply(plan)
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
            try store.undo(undoable.plan)
            self.undoable = nil
            reloadMachines()
        } catch {
            refresh()
            problems.report("take that back", error)
        }
    }

    func isClosable(_ item: Item) -> Bool {
        guard factMachines.contains(where: { $0.task == item.task }) else { return true }
        return factMachines.first?.spec.lifecycle.map { $0.open.contains(item[$0.field]) } ?? false
    }

    func isDone(_ items: [Item]) -> Bool {
        let closable = items.filter(isClosable)
        return !closable.isEmpty && closable.allSatisfy { $0.closed != nil }
    }

    func reopen(_ items: [Item]) {
        let ids = items.filter { $0.closed != nil }.compactMap(\.id)
        guard !ids.isEmpty else { return }
        do {
            try store.undo([.done(outcome: "kept"): ids])
            undoable = nil
            reloadMachines()
        } catch {
            refresh()
            problems.report("reopen that", error)
        }
    }

    func title(of item: Item) -> String {
        let field = crew.helper(task: item.task)?.spec.title
        return field.map { item[$0] } ?? item.quote
    }

    func dismissUndo() { undoable = nil }

    private func plan(for choice: FactChoice, _ items: [Item]) -> [ItemAction: [Int64]] {
        let ids = items.compactMap(\.id)
        switch choice {
        case .notRelevant: return ids.isEmpty ? [:] : [.notRelevant: ids]
        case .wrong: return ids.isEmpty ? [:] : [.wrong: ids]
        case .snooze(let day): return ids.isEmpty ? [:] : [.snooze(until: day): ids]
        case .done: return closing(items)
        }
    }

    private func closing(_ items: [Item]) -> [ItemAction: [Int64]] {
        let tasks = Set(factMachines.map(\.task))
        var plan = factMachines.first?.spec.lifecycle?.closing(items.filter { tasks.contains($0.task) }) ?? [:]
        plan.merge(DealAction.lifecycle.closing(items.filter { $0.task == DealAction.task })) { $0 + $1 }
        let findings = items.filter { !tasks.contains($0.task) && $0.task != DealAction.task && $0.closed == nil }
            .compactMap(\.id)
        if !findings.isEmpty { plan[.done(outcome: "handled")] = findings }
        return plan
    }

    func chatLines(around item: Item, reach: Int64 = 2) async throws -> [ChatLine] {
        guard item.citeFirst > 0, let helper = crew.helper(task: item.task) else {
            return []
        }
        return ChatLine.around(item, in: try await helper.source.evidence(on: item.day).lines, reach: reach)
    }

    private func reloadMachines() {
        for helper in crew.machines { helper.reload() }
        crew.machines.first?.itemsChanged()
    }
}
