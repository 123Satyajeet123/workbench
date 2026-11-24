import AgentCLI
import Foundation

@testable import WorkbenchCore

// Recall probe 2 (gates: plans/2026-11-24-core-architecture/gates/recall-probe-2.md; probe 1 is commit 731ac14b).
// SYNTHETIC days only. Needles are planted in real-length synthetic team-chat days. Arm A is the daily read; arm C is the
// read with one sentence about the founder's own messages in the brief; arm B is one gleaning pass on arm A; arm D is
// the read with the founder named by plain name, without " (You)". Each pass that finished is saved in the work folder
// and never asked again; the stores there keep every run row, whose costs make the spend. A phase runs only the jobs
// that fit the budget at the mean cost of the passes so far.
//
//   recall-probe <work folder> <report file> [days] [phases to run, such as 1,2; 0 renders the report only]
setvbuf(stdout, nil, _IOLBF, 0)
let arguments = CommandLine.arguments
guard arguments.count >= 3 else { fatalError("usage: recall-probe <work folder> <report file> [days] [phases]") }
let work = URL(filePath: arguments[1])
let reportFile = URL(filePath: arguments[2])
let dayCount = arguments.count > 3 ? Int(arguments[3])! : SyntheticDays.dates.count
let phaseNumbers = Set((arguments.count > 4 ? arguments[4] : "1,2,3,4").split(separator: ",").compactMap { Int($0) })
let callsAtOnce = 6
let seed: UInt64 = 87
let budgetUSD = 3.97
let firstGuessUSD = 0.35

let founderSentence =
    " The founder's own messages state facts too: a decision the founder makes, an order the founder gives and a plan the founder writes each give an item, as for any other person."

func spec(_ arm: Arm) -> HelperSpec {
    var spec = HelperSpec.team
    if arm == .c {
        spec.task += ".founder-sentence"
        spec.brief += founderSentence
    }
    return spec
}

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
        total + (try store(of: day).queries.runs().map(\.usage.costUSD).reduce(0, +))
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

func reader(_ arm: Arm, store: Store) -> HelperReader {
    let runner = AgentRunner(
        kind: .claude, model: "opus", effort: "medium", timeout: .seconds(300),
        workDirectory: work.appending(path: "agent-work"))
    return HelperReader(
        spec: spec(arm), model: RecordedModel(runner, store: store), zone: SyntheticDays.calendar.timeZone)
}

func read(_ job: Job) async throws -> Reading {
    let day = days[job.day]
    let store = try store(of: job.day)
    let model = { (run: RunID?) in try store.queries.runs().first { $0.id == run } }
    if job.arm == .b {
        guard let first = saved(Job(day: job.day, arm: .a, run: job.run)) else { throw MissingArmA() }
        let a = reader(.a, store: store)
        let glean = try await Gleaner(reader: a, zone: SyntheticDays.calendar.timeZone).glean(
            day: day.day, scope: "synthetic", evidence: day.evidence,
            found: first.kept.map { $0.item(task: a.spec.task, day: day) })
        let run = try model(glean.run)
        return Reading(
            day: job.day, arm: .b, run: job.run, model: run?.model ?? "", kept: glean.items.map(Kept.init),
            drops: glean.drops.map(\.rule.rawValue), usage: run?.usage ?? Usage())
    }
    let evidence = job.arm == .d ? plainFounder(day.evidence) : day.evidence
    let result = try await reader(job.arm, store: store).read(day: day.day, scope: "synthetic", evidence: evidence)
    let run = try model(result.run)
    return Reading(
        day: job.day, arm: job.arm, run: job.run, model: run?.model ?? "", kept: result.items.map(Kept.init),
        drops: try result.run.map { try store.queries.dropReasons(of: $0).map(\.rule.rawValue) } ?? [],
        usage: run?.usage ?? Usage())
}

struct MissingArmA: Error {}

/// The day as the app would show it if the founder's label were the plain name: no " (You)" after it.
func plainFounder(_ evidence: EvidenceSet) -> EvidenceSet {
    let label = Member.meera.rawValue
    let plain = String(label.dropLast(" (You)".count))
    let lines = evidence.lines.map { line in
        var line = line
        if line.line.hasPrefix(label + ":") { line.line = plain + line.line.dropFirst(label.count) }
        return line
    }
    let context = evidence.context.mapValues { names in names.map { $0 == label ? plain : $0 } }
    return EvidenceSet(lines: lines, context: context, read: evidence.read)
}

/// Runs the jobs not saved yet that fit the budget, all at once, and saves each.
func run(phase jobs: [Job], readings: [Reading]) async throws -> [String] {
    let open = jobs.filter { saved($0) == nil }
    let costs = readings.map(\.usage.costUSD)
    let each = costs.isEmpty ? firstGuessUSD : costs.reduce(0, +) / Double(costs.count)
    let fits = max(0, Int((budgetUSD - (try spent())) / each))
    let chosen = Array(open.prefix(fits))
    if chosen.count < open.count { print("budget: \(open.count - chosen.count) jobs left out of this phase") }
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

print("recall probe 2, SYNTHETIC days only, seed \(seed): \(days.count) days")
for (index, day) in days.enumerated() {
    print(
        "  day \(index) \(day.day): \(day.evidence.lines.count) lines, \(day.characters) characters, needles at "
            + "\(day.needles.map(\.line))")
}
let phases: [[Job]] = [
    days.indices.flatMap { [Job(day: $0, arm: .a, run: 1), Job(day: $0, arm: .c, run: 1)] },
    days.indices.flatMap { [Job(day: $0, arm: .a, run: 2), Job(day: $0, arm: .c, run: 2)] },
    days.indices.map { Job(day: $0, arm: .b, run: 1) },
    [Job(day: 3, arm: .d, run: 1)],
]
var failures: [String] = []
for (number, phase) in zip(1..., phases) where phaseNumbers.contains(number) {
    failures += try await run(phase: phase, readings: savedReadings())
}
let report = Report(days: days, readings: savedReadings(), seed: seed, failures: failures, spent: try spent())
let text = report.text()
print(text)
try text.write(to: reportFile, atomically: true, encoding: .utf8)
