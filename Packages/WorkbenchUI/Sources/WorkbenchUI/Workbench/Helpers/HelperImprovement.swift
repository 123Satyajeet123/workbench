import Foundation
import Observation
import WorkbenchCore

/// What a trial keeps in the store between launches.
struct SavedTrial: Codable {
    var brief: String
    var days: [String]
    var by: String?
    var why: String?
    var examples: Int?
    var runner: String?
}

/// A new version being tried on past days, and how it compares with the current one.
struct TrialRun {
    let version: HelperModel.Version
    let days: [WorkDay]
    let by: Decision.By
    let why: String
    let result: Trial
}

/// How a machine gets better: a new version is tried on past days beside the current one, and the founder decides.
/// The proposer and "learn from my marks" only start trials; nothing live changes until the founder switches.
@Observable
final class HelperImprovement {
    /// Most past days a trial reads: each is one model call.
    static let trialDays = 30
    /// Without marked training days, a trial reads this many recent ones.
    static let unmarkedTrialDays = 5
    /// Challengers tried within this window share the test's error budget.
    static let budgetWindow: TimeInterval = 90 * 86_400
    /// Research 20 §9.2 starts at three right and two wrong examples.
    static let exampleCount = 5

    private(set) var trial: TrialRun?
    private(set) var trialPhase = ReadPhase.idle
    /// The machine's decisions, newest first.
    private(set) var decisions: [Decision] = []
    /// Why nothing changed after the founder asked the proposer, or nil.
    private(set) var improveNote: String?
    /// A change the app made by itself, such as a rollback, said once on the page.
    var notice: String?

    @ObservationIgnored private let context: MachineContext

    init(context: MachineContext) { self.context = context }

    /// Loads the trial and the decisions of the machine.
    func reload() throws {
        trial = try loadTrial()
        decisions = try context.store.queries.decisions(of: context.spec.task)
    }

    /// Replays `brief` on stored evidence beside the current version; the example policy and model stay as they are.
    func startTrial(brief: String, by: Decision.By = .person, why: String = "") async {
        var version = HelperModel.Version(context.spec)
        version.brief = brief
        await startTrial(version, by: by, why: why)
    }

    /// Replays a new version (brief, example policy and model) on stored evidence beside the current one (research
    /// 20 §4): every training day the founder marked, newest first, so old marks carry over to the items both versions
    /// give; or, with no marks yet, recent training days. Held-out days are never read. Each day's reader gets the
    /// open items as of that day, and the closes it gives are not stored: nothing live changes.
    func startTrial(_ version: HelperModel.Version, by: Decision.By, why: String) async {
        let spec = context.spec
        let store = context.store
        guard version.brief.cleaned != nil, version != .init(spec), context.source.isReady, trialPhase != .reading
        else { return }
        trialPhase = .reading
        var challenger = version.apply(to: spec)
        challenger.task = Trial.task(of: spec.task)
        let scope = context.source.scope
        do {
            var days = try store.queries.markedDays(of: spec.task).filter { EvalSplit($0) == .dev }
                .prefix(Self.trialDays)
            if days.isEmpty {
                let since = context.today.adding(days: -14)
                days = Set(try store.queries.items(of: spec.task, since: since).map(\.day)).filter {
                    EvalSplit($0) == .dev
                }
                .sorted(by: >).prefix(Self.unmarkedTrialDays)
            }
            try store.discardTrialItems(of: spec.task)
            let reader = HelperReader(spec: challenger, model: context.makeModel(try context.runner(for: version)))
            for day in days {
                _ = try await context.grant()
                var result = try await reader.read(
                    day: day, scope: scope, evidence: try await context.source.evidence(on: day),
                    marked: try context.marked(), open: try store.queries.openItems(readBy: spec, asOf: day))
                result.links = []
                try store.saveReading(
                    result, of: challenger, day: day, scope: scope, grant: try await context.grant())
            }
            try store.log(
                Decision(
                    at: store.clock(), task: spec.task, kind: .trial, by: by, brief: version.brief,
                    parentBrief: spec.brief,
                    detail: version.detail(parent: .init(spec)).merging(["days": String(days.count), "why": why]) {
                        a, _ in a
                    }))
            try MachineKey.trial(spec.task).save(
                SavedTrial(
                    brief: version.brief, days: days.map(\.description), by: by.rawValue, why: why,
                    examples: version.examples, runner: version.runner),
                to: store)
            trialPhase = .idle
            context.reload()
            context.itemsChanged()
        } catch {
            trialPhase = .idle
            context.problems.report("try the new version", error)
        }
    }

    /// Another model on trial: the same brief and examples, read by `choice` on past days. The days' evidence goes to
    /// that model's vendor, so this runs only on the founder's click.
    func tryModel(_ choice: ModelChoice) async {
        var version = HelperModel.Version(context.spec)
        version.runner = choice.id
        await startTrial(version, by: .person, why: "Try \(choice.title)")
    }

    /// Learning from marks is a trial like any change: the same brief with marked examples, judged on past days.
    func learnFromMarks() async {
        var version = HelperModel.Version(context.spec)
        version.examples = Self.exampleCount
        await startTrial(version, by: .person, why: "Learn from my marked examples")
    }

    /// The proposer reads the founder's marks on training days and, when it finds one clear fix, starts a trial of it.
    func improve() async {
        guard trial == nil, trialPhase != .reading else { return }
        improveNote = nil
        let spec = context.spec
        do {
            let marked = try context.store.queries.items(of: spec.task, since: context.today.adding(days: -60))
            let improver = Improver(model: context.makeModel(try ModelChoice.saved(in: context.store)))
            let (edit, run) = try await improver.propose(spec: spec, marked: marked)
            guard let edit else {
                improveNote =
                    run == nil
                    ? "Mark at least \(Improver.minimumWrong) wrong items on training days first."
                    : "No clear fix in your marks yet."
                return
            }
            await startTrial(brief: edit.apply(to: spec.brief), by: .proposer, why: edit.why)
        } catch {
            context.problems.report("look for an improvement", error)
        }
    }

    /// The founder keeps the current brief: the trial's items go, and the decision is logged.
    func keepCurrent() {
        if let trial {
            let spec = context.spec
            context.problems.attempt("log the decision") {
                try context.store.log(
                    Decision(
                        at: context.store.clock(), task: spec.task, kind: .reject, by: .person,
                        brief: trial.version.brief, parentBrief: spec.brief, detail: Self.counts(trial.result)))
            }
        }
        endTrial()
    }

    /// Removes the trial's items and its record; the current version stays as it is.
    func endTrial() {
        let task = context.spec.task
        context.problems.attempt("end the trial") { try context.store.delete(.machine(Trial.task(of: task))) }
        context.problems.attempt("end the trial") { try MachineKey.trial(task).clear(in: context.store) }
        context.reload()
        context.itemsChanged()
    }

    static func counts(_ trial: Trial) -> [String: String] {
        [
            "same": String(trial.same), "better": String(trial.better), "worse": String(trial.worse),
            "verdict": trial.verdict.rawValue,
        ]
    }

    /// The trial with its marked differences in the order the founder gave the marks.
    private func loadTrial() throws -> TrialRun? {
        let spec = context.spec
        let store = context.store
        guard let saved = try MachineKey.trial(spec.task).load(from: store) else { return nil }
        let days = saved.days.compactMap { WorkDay($0) }
        var current: [Item] = []
        var challenger: [Item] = []
        for day in days {
            current += try store.queries.items(of: spec.task, day: day, scope: context.source.scope)
            challenger += try store.queries.items(of: Trial.task(of: spec.task), day: day, scope: context.source.scope)
        }
        let order = try store.queries.markOrder(of: (current + challenger).compactMap(\.id))
        let since = store.clock().addingTimeInterval(-Self.budgetWindow)
        let tried = try store.queries.decisions(of: spec.task).filter { $0.kind == .trial && $0.at >= since }.count
        let result = Trial(
            current: current, challenger: challenger, citation: spec.citation, choices: spec.choiceFields,
            markOrder: order,
            threshold: EProcess.threshold(challengers: tried))
        let version = HelperModel.Version(brief: saved.brief, examples: saved.examples, runner: saved.runner)
        return TrialRun(
            version: version, days: days, by: saved.by.flatMap(Decision.By.init) ?? .person, why: saved.why ?? "",
            result: result)
    }
}
