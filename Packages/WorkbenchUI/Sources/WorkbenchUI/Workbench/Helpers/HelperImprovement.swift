import Foundation
import Observation
import WorkbenchCore

struct SavedTrial: Codable {
    var brief: String
    var days: [String]
    var by: String?
    var why: String?
    var examples: Int?
    var runner: String?
}

struct TrialRun {
    let version: HelperModel.Version
    let days: [WorkDay]
    let by: Decision.By
    let why: String
    let result: Trial
}

@Observable
final class HelperImprovement {
    static let trialDays = 30
    static let unmarkedTrialDays = 5
    static let budgetWindow: TimeInterval = 90 * 86_400
    static let exampleCount = 5

    private(set) var trial: TrialRun?
    private(set) var trialPhase = ReadPhase.idle
    private(set) var decisions: [Decision] = []
    private(set) var improveNote: String?
    var notice: String?

    @ObservationIgnored private let context: MachineContext

    init(context: MachineContext) { self.context = context }

    func reload() throws {
        trial = try loadTrial()
        decisions = try context.store.queries.decisions(of: context.spec.task)
    }

    func startTrial(brief: String, by: Decision.By = .person, why: String = "") async {
        var version = HelperModel.Version(context.spec)
        version.brief = brief
        await startTrial(version, by: by, why: why)
    }

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
            let reader = HelperReader(spec: challenger, model: context.makeModel(try context.runner(for: version)))
            for day in days {
                _ = try await context.grant()
                var result = try await reader.read(
                    day: day, scope: scope, evidence: try await context.source.evidence(on: day),
                    marked: try context.marked(), open: try store.queries.openItems(readBy: spec, asOf: day))
                result.closes = []
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

    func tryModel(_ choice: ModelChoice) async {
        var version = HelperModel.Version(context.spec)
        version.runner = choice.id
        await startTrial(version, by: .person, why: "Try \(choice.title)")
    }

    func learnFromMarks() async {
        var version = HelperModel.Version(context.spec)
        version.examples = Self.exampleCount
        await startTrial(version, by: .person, why: "Learn from my marked examples")
    }

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
