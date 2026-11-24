import Foundation
import Observation
import WorkbenchCore

@Observable
final class HelperSchedule {
    var nudge = NudgeSchedule() {
        didSet {
            context.problems.attempt("save the nudge") {
                try MachineKey.nudge(context.spec.task).save(nudge, to: context.store)
            }
        }
    }
    var watch = WatchSchedule() {
        didSet {
            context.problems.attempt("save the reading hours") {
                try MachineKey.watch(context.spec.task).save(watch, to: context.store)
            }
        }
    }

    /// Finding startups once a week by itself, for an outbound machine. Off until the investor turns it on.
    var weekly = WeeklySearch() {
        didSet {
            context.problems.attempt("save the weekly search") {
                try MachineKey.weekly(context.spec.task).save(weekly, to: context.store)
            }
        }
    }

    @ObservationIgnored private let context: MachineContext
    @ObservationIgnored private let reading: HelperReading
    @ObservationIgnored private let ticker = Ticker()

    init(context: MachineContext, reading: HelperReading) {
        self.context = context
        self.reading = reading
        do {
            nudge = try MachineKey.nudge(context.spec.task).load(from: context.store) ?? NudgeSchedule()
            watch =
                try MachineKey.watch(context.spec.task).load(from: context.store)
                ?? .standard(for: context.spec.source)
            weekly = try MachineKey.weekly(context.spec.task).load(from: context.store) ?? WeeklySearch()
        } catch {
            context.problems.report("read the saved nudge", error)
        }
    }

    func start() {
        ticker.start(waitingFirst: true) { [weak self] in
            await self?.readIfDue()
            await self?.nudgeIfDue()
            await self?.findIfDue()
        }
    }

    func stop() { ticker.stop() }

    /// Turning the nudge on asks macOS for permission the first time; while macOS blocks it, it waits and turns on
    /// once the founder allows notifications.
    func setNudge(on: Bool) async {
        guard on else {
            nudge.isOn = false
            return
        }
        await context.notifications.whenAllowed { [weak self] in self?.nudge.isOn = true }
    }

    /// Reading through the day does not wait for notifications; a machine that alerts asks for them, and its alert is
    /// skipped while they are off.
    func setWatch(on: Bool) async {
        watch.isOn = on
        if on, context.spec.tones.values.contains(.bad) { _ = await context.notifications.isAllowed() }
    }

    /// Reads the lines that are new since the last reading, when the reading hours say so, and tells the founder
    /// about new items whose value the spec marks bad (a blocker, for the team machine).
    func readIfDue() async {
        let now = context.store.clock()
        let spec = context.spec
        let watchedKey = MachineKey.watched(spec.task)
        guard watch.isOn, context.source.isReady, !context.isPaused, reading.phase != .reading else { return }
        let lastRead = (try? watchedKey.load(from: context.store)).flatMap { $0 }
        guard watch.isDue(at: now, lastRead: lastRead) else { return }
        context.problems.attempt("save the reading time") { try watchedKey.save(now, to: context.store) }
        let today = WorkDay(containing: now)
        let before = Set(context.items(on: today).compactMap(\.id))
        guard await reading.read(today) else { return }
        let alarming = context.items(on: today).filter { item in
            !before.contains(item.id ?? -1) && item.fields.values.contains { spec.tones[$0] == .bad }
        }
        guard !alarming.isEmpty, await context.notifications.isAllowed() else { return }
        let group: String? = if case .board(let field, _) = spec.view { field } else { nil }
        let lines = alarming.map { item in
            [group.map { item[$0] } ?? "", item[spec.title]].filter { !$0.isEmpty }.joined(separator: ": ")
        }
        await post(lines.joined(separator: "\n"), failure: "show the alert")
    }

    /// Finds startups when the weekly search is on and a week has passed. The time is saved first, so a failed run
    /// waits a week, not a minute. The monthly cap still applies.
    func findIfDue() async {
        let now = context.store.clock()
        let ranKey = MachineKey.weeklyRan(context.spec.task)
        guard weekly.isOn, context.spec.source.findsStartups, context.source.isReady, !context.isPaused,
            reading.phase != .reading
        else { return }
        let lastRan = (try? ranKey.load(from: context.store)).flatMap { $0 }
        guard weekly.isDue(at: now, lastRan: lastRan) else { return }
        context.problems.attempt("save the search time") { try ranKey.save(now, to: context.store) }
        await reading.read(context.today)
    }

    /// Reads today and names who has no item. The day is marked first, so a failure nudges once, not every minute.
    func nudgeIfDue() async {
        let now = context.store.clock()
        let spec = context.spec
        let nudgedKey = MachineKey.nudged(spec.task)
        guard let message = spec.nudge?.message, context.source.isReady, !context.isPaused, nudge.isOn else { return }
        let lastSent: WorkDay?
        do {
            lastSent = try nudgedKey.load(from: context.store)
        } catch {
            context.problems.report("read the nudge", error)
            return
        }
        guard nudge.isDue(at: now, lastSent: lastSent) else { return }
        let today = WorkDay(containing: now)
        context.problems.attempt("save the nudge") { try nudgedKey.save(today, to: context.store) }
        let body: String
        if await reading.read(today) {
            let missing = context.missing(on: today)
            body =
                missing.isEmpty
                ? "Everyone has \(spec.itemsNoun) today." : "\(message) \(missing.formatted(.list(type: .and)))."
        } else {
            guard !Task.isCancelled else { return }
            body = context.problems.text ?? "Could not read today."
        }
        await post(body, failure: "show the nudge")
    }

    private func post(_ body: String, failure: String) async {
        do {
            try await context.notifications.post(
                title: context.name, body: body, page: .machine(context.machine.id))
        } catch {
            context.problems.report(failure, error)
        }
    }
}
