import AgentCLI
import Foundation

@testable import WorkbenchCore

// Recall probe 3: the member-identity fix (plans/2026-11-24-core-architecture/recall-probe-2.md has the defect and the
// "before"). SYNTHETIC days only, seed 87, the days of probe 2. Arm A is the saved read of probe 2: the code before the
// fix, the founder shown as "Meera Rao (You)". Arm Fixed is this branch: the founder shown by plain name, and a time
// schema that cannot write a part of the day with a day. Copy probe 2's `day-N-A-run-1.json` files into the work folder
// first. Each pass that finished is saved there and never asked again; the stores there keep every run row, whose costs
// make the spend. A pass runs only while the budget lasts.
//
//   recall-probe <work folder> <report file> [days] [report-only]
setvbuf(stdout, nil, _IOLBF, 0)
let arguments = CommandLine.arguments
guard arguments.count >= 3 else { fatalError("usage: recall-probe <work folder> <report file> [days] [report-only]") }
let work = URL(filePath: arguments[1])
let reportFile = URL(filePath: arguments[2])
let dayCount = arguments.count > 3 ? Int(arguments[3])! : SyntheticDays.dates.count
let reportOnly = arguments.count > 4 && arguments[4] == "report-only"
let callsAtOnce = 6
let seed: UInt64 = 87
let budgetUSD = 2.0
let firstGuessUSD = 0.35

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

func spent() throws -> Double {
    try days.indices.reduce(0) { total, day in
        total + (try store(of: day).queries.runs().compactMap(\.usage?.costUSD).reduce(0, +))
    }
}

func file(_ job: Job) -> URL { work.appending(path: "day-\(job.day)-\(job.arm.rawValue)-run-\(job.run).json") }

func saved(_ job: Job) -> Reading? {
    (try? Data(contentsOf: file(job))).flatMap { try? JSONDecoder().decode(Reading.self, from: $0) }
}

struct Job {
    let day: Int
    let arm: Arm
    let run: Int
}

func reader(store: Store) -> HelperReader {
    let runner = AgentRunner(
        kind: .claude, model: "opus", effort: "medium", timeout: .seconds(300),
        workDirectory: work.appending(path: "agent-work"))
    return HelperReader(
        spec: .team, model: RecordedModel(runner, store: store), zone: SyntheticDays.calendar.timeZone)
}

func read(_ job: Job) async throws -> Reading {
    let day = days[job.day]
    let store = try store(of: job.day)
    let result = try await reader(store: store).read(day: day.day, scope: "synthetic", evidence: day.evidence)
    let run = try store.queries.runs().first { $0.id == result.run }
    return Reading(
        day: job.day, arm: job.arm, run: job.run, model: run?.model ?? "", kept: result.items.map(Kept.init),
        drops: try result.run.map { try store.queries.dropReasons(of: $0).map(\.rule.rawValue) } ?? [],
        usage: run?.usage ?? Usage())
}

/// Runs the jobs not saved yet that fit the budget, all at once, and saves each.
func run(jobs: [Job], readings: [Reading]) async throws -> [String] {
    let open = jobs.filter { saved($0) == nil }
    let costs = readings.map(\.usage.costUSD)
    let each = costs.isEmpty ? firstGuessUSD : costs.reduce(0, +) / Double(costs.count)
    let fits = max(0, Int((budgetUSD - (try spent())) / each))
    let chosen = Array(open.prefix(fits))
    if chosen.count < open.count { print("budget: \(open.count - chosen.count) jobs left out") }
    var failures: [String] = []
    for start in stride(from: 0, to: chosen.count, by: callsAtOnce) {
        failures += await withTaskGroup(of: String?.self) { group in
            for job in chosen[start..<min(start + callsAtOnce, chosen.count)] {
                group.addTask { await save(job) }
            }
            var failures: [String] = []
            for await failure in group { if let failure { failures.append(failure) } }
            return failures
        }
    }
    return failures
}

/// Reads one job and saves it. Returns the failure, if any.
func save(_ job: Job) async -> String? {
    do {
        let reading = try await read(job)
        try JSONEncoder().encode(reading).write(to: file(job))
        print("day \(job.day) arm \(job.arm.rawValue) run \(job.run): \(reading.kept.count) kept")
        return nil
    } catch {
        return "day \(job.day) arm \(job.arm.rawValue) run \(job.run): \(error)"
    }
}

func savedReadings() -> [Reading] {
    days.indices.flatMap { day in
        Arm.allCases.flatMap { arm in (1...2).compactMap { saved(Job(day: day, arm: arm, run: $0)) } }
    }
}

print("recall probe 3, SYNTHETIC days only, seed \(seed): \(days.count) days")
for (index, day) in days.enumerated() {
    print(
        "  day \(index) \(day.day): \(day.evidence.lines.count) lines, \(day.characters) characters, needles at "
            + "\(day.needles.map(\.line))")
}
var failures: [String] = []
if !reportOnly {
    failures = try await run(jobs: days.indices.map { Job(day: $0, arm: .fixed, run: 1) }, readings: savedReadings())
}
let report = Report(days: days, readings: savedReadings(), seed: seed, failures: failures, spent: try spent())
let text = report.text()
print(text)
try text.write(to: reportFile, atomically: true, encoding: .utf8)
