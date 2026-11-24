import Foundation

@testable import WorkbenchCore

public struct PageEvalOptions: Sendable {
    public var models: [String]
    public var runs: Int
    /// How many requests are in flight at once.
    public var parallelism: Int
    /// One run of one model in one arm that costs more than this stops the eval.
    public var costLimitUSD: Double
    /// The whole eval stops when it has cost more than this.
    public var totalCostLimitUSD: Double
    public var arms: [PageEvalArm]
    /// The groups to run; nil runs every group.
    public var groups: [String]?
    /// Where the Claude CLI and the tool server are; needed for the `tools` arm.
    public var toolSetup: PageEvalToolSetup?

    public init(
        models: [String], runs: Int, parallelism: Int, costLimitUSD: Double, totalCostLimitUSD: Double = .infinity,
        arms: [PageEvalArm] = [.one], groups: [String]? = nil, toolSetup: PageEvalToolSetup? = nil
    ) {
        self.models = models
        self.runs = runs
        self.parallelism = parallelism
        self.costLimitUSD = costLimitUSD
        self.totalCostLimitUSD = totalCostLimitUSD
        self.arms = arms
        self.groups = groups
        self.toolSetup = toolSetup
    }

    /// The tasks of the chosen groups, in the order of `PageEvalTask.all`.
    var tasks: [PageEvalTask] { PageEvalTask.all.filter { groups?.contains($0.group) ?? true } }
}

/// How the model gets the facts. `one`: one call with the page, the catalog and the facts in the input. `tools`: the
/// Claude CLI runs a loop over three read-only tools and returns the same operations by the same schema.
public enum PageEvalArm: String, Codable, Sendable, CaseIterable {
    case one, tools
}

public enum PageEvaluation {
    /// The names of the groups of tasks, in order.
    public static var groupNames: [String] {
        PageEvalTask.all.reduce(into: [String]()) { if !$0.contains($1.group) { $0.append($1.group) } }
    }
}

/// The composer eval: every task, for every model, `runs` times, each attempt on a new store holding the fixture.
public enum PageEval {
    /// The model of the app for a store and a model name. The runner passes the app's own `ModelChoice`.
    public typealias MakeModel = @MainActor @Sendable (Store, String) -> RecordedModel

    public static func run(
        _ options: PageEvalOptions, makeModel: @escaping MakeModel, progress: @escaping @Sendable (String) -> Void
    ) async throws -> PageEvalResult {
        let demo = try PageEvalFact.load()
        let tasks = options.tasks
        var records: [PageEvalRecord] = []
        for model in options.models {
            for run in 1...options.runs {
                for arm in options.arms {
                    let made = try await inParallel(tasks, limit: options.parallelism) { task in
                        try await attempt(
                            task, arm: arm, model: model, run: run, demo: demo, options: options, makeModel: makeModel)
                    }
                    let cost = made.map(\.costUSD).reduce(0, +)
                    progress(
                        String(
                            format: "%@ %@ run %d: %d of %d pass, %.2f USD", model, arm.rawValue, run,
                            made.filter(\.passed).count, made.count, cost))
                    records += made
                    let spent = records.map(\.costUSD).reduce(0, +)
                    if cost > options.costLimitUSD || spent > options.totalCostLimitUSD {
                        throw PageEvalError.costLimit(model: model, run: run, usd: max(cost, spent))
                    }
                }
            }
        }
        return PageEvalResult(
            date: Date(), note: "dev, synthetic fixture; every number is dev", models: options.models,
            arms: options.arms, runs: options.runs, factCount: demo.count, records: records,
            instructions: ["one": PageComposer.instructions, "tools": PageEvalToolInstructions.text],
            summaries: options.models.flatMap { model in
                options.arms.map {
                    PageEvalModelSummary(model: model, arm: $0, tasks: tasks, runs: options.runs, records: records)
                }
            })
    }

    /// One request on a store of its own, so no attempt sees the proposal, the run or the cache of another.
    static func attempt(
        _ task: PageEvalTask, arm: PageEvalArm, model: String, run: Int, demo: [PageEvalFact],
        options: PageEvalOptions, makeModel: MakeModel
    ) async throws -> PageEvalRecord {
        let directory = FileManager.default.temporaryDirectory.appending(path: "page-eval-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try await PageEvalFixture.make(
            task.page, factSet: task.facts, facts: task.facts.facts(demo: demo), in: directory)
        let call: PageEvalCall
        switch arm {
        case .one: call = try await oneCall(task, model: model, fixture: fixture, makeModel: makeModel)
        case .tools:
            guard let setup = options.toolSetup else { throw PageEvalError.fixture("the tools arm has no setup") }
            call = try await PageEvalToolArm.call(task.request, model: model, fixture: fixture, setup: setup)
        }
        return try record(task, arm: arm, model: model, run: run, fixture: fixture, call: call)
    }

    /// Arm one: the composer as the app calls it, on a model that records its run.
    private static func oneCall(
        _ task: PageEvalTask, model: String, fixture: PageEvalFixture, makeModel: MakeModel
    ) async throws -> PageEvalCall {
        try fixture.store.confirmModelTerms()
        let composer = PageComposer(model: await makeModel(fixture.store, model))
        let clock = ContinuousClock()
        let begun = clock.now
        var call = PageEvalCall()
        do { call.proposal = try await fixture.compose(task.request, with: composer) } catch {
            call.failure = "\(error)"
        }
        call.wallSeconds = begun.duration(to: clock.now).seconds
        let row = try fixture.store.queries.runs().first { $0.task == PageComposer.task && $0.model != "synthetic" }
        let text = try row.flatMap { try fixture.store.queries.runText(of: $0.id) }
        call.reply = text?.reply.flatMap { try? JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) }
        call.windowLines = try row.map { try fixture.store.queries.window(of: $0.id).count } ?? 0
        call.usage = row?.usage ?? Usage()
        call.runRowSeconds = row.flatMap { run in run.endedAt.map { $0.timeIntervalSince(run.startedAt) } } ?? 0
        return call
    }

    private static func record(
        _ task: PageEvalTask, arm: PageEvalArm, model: String, run: Int, fixture: PageEvalFixture, call: PageEvalCall
    ) throws -> PageEvalRecord {
        let proposal = call.proposal
        let notes =
            proposal == nil
            ? fixture.start.notes : try fixture.store.queries.page(of: fixture.page, for: fixture.viewer).notes
        return PageEvalRecord(
            model: model, arm: arm.rawValue, task: task.name, group: task.group, run: run, request: task.request,
            page: task.page.rawValue,
            passed: proposal.map {
                task.passes(PageEvalOutcome(start: fixture.start, facts: fixture.facts, proposal: $0))
            }
                ?? false,
            callFailure: call.failure, reply: call.reply,
            verdicts: proposal.map(PageEvalRecord.verdicts) ?? [], note: proposal?.note ?? "",
            resultPage: PageEvalRecord.blocks(
                of: proposal?.page ?? fixture.start.page, notes: notes, fixtureIDs: fixture.fixtureIDs),
            windowLines: call.windowLines, costUSD: call.usage.costUSD, inputTokens: call.usage.inputTokens,
            cacheReadTokens: call.usage.cacheReadTokens, cacheWriteTokens: call.usage.cacheWriteTokens,
            outputTokens: call.usage.outputTokens, turns: call.turns, toolCalls: call.toolCalls,
            refusedToolCalls: call.refusedToolCalls, toolErrors: call.toolErrors,
            permissionDenials: call.permissionDenials, unfetchedNames: call.unfetchedNames,
            runRowSeconds: call.runRowSeconds, wallSeconds: call.wallSeconds)
    }

    /// `work` on every item, with at most `limit` at a time; the results are in the order of the items.
    static func inParallel<Item: Sendable, Output: Sendable>(
        _ items: [Item], limit: Int, _ work: @escaping @Sendable (Item) async throws -> Output
    ) async throws -> [Output] {
        try await withThrowingTaskGroup(of: (Int, Output).self) { group in
            var results = [Output?](repeating: nil, count: items.count)
            var next = 0
            func startNext() {
                guard next < items.count else { return }
                let (index, item) = (next, items[next])
                next += 1
                group.addTask { (index, try await work(item)) }
            }
            for _ in 0..<min(limit, items.count) { startNext() }
            while let (index, output) = try await group.next() {
                results[index] = output
                startNext()
            }
            return results.compactMap { $0 }
        }
    }
}
