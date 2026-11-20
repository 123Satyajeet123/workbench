import Foundation
import Observation
import WorkbenchCore

/// What the founder can do with a fact line. A summary line acts on the facts it cites.
enum FactChoice: Equatable {
    case done, notRelevant, wrong
    case snooze(until: WorkDay)
}

/// A line of the chat a fact came from.
struct ChatLine: Identifiable, Equatable {
    var id: Int64
    var time: Date
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

/// One summary line with the facts it cites that are still listed.
struct SummaryRow: Identifiable {
    var summary: Summary
    var line: Summary.Line
    var facts: [Item]
    var openCount: Int

    var id: String { summary.scope }
    var subject: String { summary.subject }
}

/// What Today, People and Projects show: the facts of the last seven days, the day's summaries, and what needs the
/// founder. It reads the store; the one model call it may start is the day's missing summaries. An action is a mark
/// or an event, and can be taken back.
@Observable
final class TodayModel {
    /// How many days People and Projects reach back.
    static let days = 7

    struct Undo: Equatable {
        var plan: [ItemAction: [Int64]]
        var text: String
    }

    private(set) var today: WorkDay
    private(set) var needs: [Need] = []
    private(set) var team: [SummaryRow] = []
    /// Today's facts of the people with no summary line, so a day with facts never looks empty.
    private(set) var unsummarized: [FactGroup] = []
    private(set) var isSummarizing = false
    private(set) var projects: [SummaryRow] = []
    private(set) var people: [FactGroup] = []
    private(set) var projectGroups: [FactGroup] = []
    private(set) var undoable: Undo?
    private(set) var problem: String?
    /// Counts each load, so a view can animate what changed between two loads.
    private(set) var revision = 0

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let crew: Crew
    @ObservationIgnored private var daysAsked: Set<WorkDay> = []

    init(store: Store, crew: Crew) {
        self.store = store
        self.crew = crew
        today = WorkDay(containing: store.clock())
        refresh()
        crew.onItemsChanged { [weak self] in self?.refresh() }
    }

    var isEmpty: Bool { needs.isEmpty && team.isEmpty && unsummarized.isEmpty && projects.isEmpty }

    private var factHelper: HelperModel? { crew.machines.first { $0.machine.template == HelperSpec.team.task } }
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

    private func load() throws {
        let now = store.clock()
        today = WorkDay(containing: now)
        guard let machine = factMachine else { return clear() }
        let lifecycle = machine.spec.lifecycleOrNone
        let facts = try recentFacts(of: machine, lifecycle: lifecycle, since: today.adding(days: 1 - Self.days))
        let findings = try sentinelTask.map { try store.queries.items(of: $0, on: today) } ?? []
        let listed = facts.filter { $0.isListed(at: now) }
        needs = Needs.pick(facts: facts, findings: findings, today: today, now: now)
        people = group(facts, by: machine.spec.memberField, lifecycle, now)
        projectGroups = group(facts, by: machine.spec.labelField, lifecycle, now)
        team = try rows(machine.spec.memberField, of: machine, day: today, listed: listed, groups: people)
        unsummarized = withoutSummary(facts.filter { $0.day == today }, machine, lifecycle, now)
        projects = try rows(machine.spec.labelField, of: machine, day: today, listed: listed, groups: projectGroups)
    }

    private func clear() {
        needs = []
        team = []
        unsummarized = []
        projects = []
        people = []
        projectGroups = []
    }

    /// The facts of the window and every fact still open, however old.
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

    /// One row per scope that has a short line with a fact still listed.
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
            try store.apply(plan)
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
            try store.undo(undoable.plan)
            self.undoable = nil
            reloadMachines()
        } catch {
            problem = "Could not take that back: \(error.localizedDescription)"
            refresh()
        }
    }

    /// The line a fact or finding shows: the title field of the machine that found it.
    func title(of item: Item) -> String {
        let field = crew.machines.first { $0.spec.task == item.task }?.spec.title
        return field.map { item[$0] } ?? item.quote
    }

    func dismissUndo() { undoable = nil }
    func dismissProblem() { problem = nil }

    private func plan(for choice: FactChoice, _ items: [Item]) -> [ItemAction: [Int64]] {
        let ids = items.compactMap(\.id)
        switch choice {
        case .notRelevant: return ids.isEmpty ? [:] : [.notRelevant: ids]
        case .wrong: return ids.isEmpty ? [:] : [.wrong: ids]
        case .snooze(let day): return ids.isEmpty ? [:] : [.snooze(until: day): ids]
        case .done: return closing(items)
        }
    }

    /// A fact closes with its lifecycle's outcome; a finding, which has no lifecycle, is handled.
    private func closing(_ items: [Item]) -> [ItemAction: [Int64]] {
        let task = factMachine?.task
        var plan = factMachine?.spec.lifecycle?.closing(items.filter { $0.task == task }) ?? [:]
        let findings = items.filter { $0.task != task && $0.closed == nil }.compactMap(\.id)
        if !findings.isEmpty { plan[.done(outcome: "handled")] = findings }
        return plan
    }

    /// The chat lines around the ones a fact cites, as its source has them now. Empty when the fact cites no line or
    /// its machine is gone.
    func chatLines(around item: Item, reach: Int64 = 2) async throws -> [ChatLine] {
        guard item.citeFirst > 0, let helper = crew.machines.first(where: { $0.spec.task == item.task }) else {
            return []
        }
        return ChatLine.around(item, in: try await helper.source.evidence(on: item.day).lines, reach: reach)
    }

    /// The machines' own pages read the same rows, so they follow an action too.
    private func reloadMachines() {
        for helper in crew.machines { helper.reload() }
        crew.machines.first?.itemsChanged()
    }
}
