import AgentCLI
import Foundation

@testable import WorkbenchCore

// Recall probe 1 (research T3 probes 1 and 2; gates: plans/2026-11-24-core-architecture/gates/recall-probe-1.md).
// SYNTHETIC days only. Needles are planted in synthetic team-chat days; the daily read (arm A) and the same read plus one
// add-only gleaning pass (arm B) read each day twice. Each finished day run is saved in the work folder and never asked
// again; the stores there keep every run row, whose costs make the spend.
//
//   recall-probe <work folder> <report file> [days] [runs]
setvbuf(stdout, nil, _IOLBF, 0)
let arguments = CommandLine.arguments
guard arguments.count >= 3 else { fatalError("usage: recall-probe <work folder> <report file> [days] [runs]") }
let work = URL(filePath: arguments[1])
let reportFile = URL(filePath: arguments[2])
let dayCount = arguments.count > 3 ? Int(arguments[3])! : SyntheticDays.dates.count
let runCount = arguments.count > 4 ? Int(arguments[4])! : 2
let seed: UInt64 = 86
let budgetUSD = 3.8
let modelName = "opus"
let effort = "medium"

let days = SyntheticDays.make(seed: seed, days: dayCount)
try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

func store(of day: Int) throws -> Store {
    let store = try Store(directory: work.appending(path: "day-\(day)"))
    // At the founder's instruction the probe runs his Claude sign-in on synthetic text only; the conditions the app asks
    // for are recorded in this scratch store.
    try store.confirmModelTerms()
    try store.saveProfile(.continuity)
    try store.savePolicy(CapturePolicy(switches: [.whatsapp: true]))
    return store
}

/// The spend so far: the cost of every run row in every day's store.
func spent() throws -> Double {
    try days.indices.reduce(0) { total, day in
        total + (try store(of: day).queries.runs().map(\.usage.costUSD).reduce(0, +))
    }
}

func savedRun(day: Int, run: Int) -> URL { work.appending(path: "day-\(day)-run-\(run).json") }

func usage(of run: RunID?, in store: Store) throws -> Usage {
    try store.queries.runs().first { $0.id == run }?.usage ?? Usage()
}

func read(day index: Int, run: Int) async throws -> DayRun {
    let file = savedRun(day: index, run: run)
    if let data = try? Data(contentsOf: file) { return try JSONDecoder().decode(DayRun.self, from: data) }
    let total = try spent()
    guard total < budgetUSD else { throw BudgetSpent(total: total) }
    let day = days[index]
    let store = try store(of: index)
    let runner = AgentRunner(
        kind: .claude, model: modelName, effort: effort, timeout: .seconds(300),
        workDirectory: work.appending(path: "agent-work"))
    let reader = HelperReader(
        spec: .team, model: RecordedModel(runner, store: store), zone: SyntheticDays.calendar.timeZone)
    let first = try await reader.read(day: day.day, scope: "synthetic", evidence: day.evidence)
    let glean = try await Gleaner(reader: reader, zone: SyntheticDays.calendar.timeZone).glean(
        day: day.day, scope: "synthetic", evidence: day.evidence, found: first.items)
    let result = DayRun(
        day: index, run: run, model: try store.queries.runs().first { $0.id == first.run }?.model ?? "",
        first: first.items.map(Kept.init),
        firstDrops: try first.run.map { try store.queries.dropReasons(of: $0).map(\.rule.rawValue) } ?? [],
        firstUsage: try usage(of: first.run, in: store), gleaned: glean.items.map(Kept.init),
        gleanDrops: glean.drops.map(\.rule.rawValue), gleanUsage: try usage(of: glean.run, in: store))
    try JSONEncoder().encode(result).write(to: file)
    print("day \(index) run \(run): first \(result.first.count) kept, gleaned \(result.gleaned.count) kept")
    return result
}

struct BudgetSpent: Error { let total: Double }

struct RunFailure: Error { let day: Int, run: Int, error: String }

print("recall probe 1, SYNTHETIC days only, seed \(seed): \(days.count) days, \(runCount) runs")
for (index, day) in days.enumerated() {
    print("  day \(index) \(day.day): \(day.evidence.lines.count) lines, needles at \(day.needles.map(\.line))")
}
var results: [DayRun] = []
var failures: [String] = []
// Days run in parallel; the runs of one day run in order, so a day's second run never starts before its first is saved.
await withTaskGroup(of: [Result<DayRun, any Error>].self) { group in
    for index in days.indices {
        group.addTask {
            var done: [Result<DayRun, any Error>] = []
            for run in 1...runCount {
                do { done.append(.success(try await read(day: index, run: run))) } catch {
                    done.append(.failure(RunFailure(day: index, run: run, error: "\(error)")))
                }
            }
            return done
        }
    }
    for await batch in group {
        for outcome in batch {
            switch outcome {
            case .success(let result): results.append(result)
            case .failure(let error): failures.append("\(error)")
            }
        }
    }
}

let report = Report(days: days, results: results, runs: runCount, seed: seed, failures: failures, spent: try spent())
let text = report.text()
print(text)
try text.write(to: reportFile, atomically: true, encoding: .utf8)
