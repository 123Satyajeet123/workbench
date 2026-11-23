import AgentCLI
import Evals
import Foundation

@testable import WorkbenchCore

// The label-free probe of the stage 2 rubric judge (ADR-020 §8, P-J2 first half). Dev data only; every number is dev.
// Notes are written by two model families about dev companies, from the dev passages. Each judge reads each note in two
// orders and, for the base arm, three runs. Variants of a note (padded, shortened, a fake claim of authority, in Hindi,
// in Hinglish) show what moves the verdicts. No label of the person is used.
//
//   judge-probe <dev folder> <report.txt>
setvbuf(stdout, nil, _IOLBF, 0)
guard CommandLine.arguments.count == 3 else { fatalError("usage: judge-probe <dev folder> <report.txt>") }
let devFolder = URL(filePath: CommandLine.arguments[1])
let reportFile = URL(filePath: CommandLine.arguments[2])
var report: [String] = []
nonisolated(unsafe) var failedCalls = 0

@MainActor func say(_ line: String) {
    print(line)
    report.append(line)
}

let scratch = FileManager.default.temporaryDirectory.appending(path: "judge-probe-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: scratch) }
let store = try Store(directory: scratch)
// The probe runs the founder's own Claude and Codex sign-ins, at the founder's instruction, on public dev text only. The
// conditions the app asks for are recorded in this scratch store, which is deleted at the end.
try store.confirmModelTerms()

let families = [
    Family(name: "claude", runner: AgentRunner(kind: .claude, model: "sonnet", effort: "low", timeout: .seconds(600))),
    Family(
        name: "codex", runner: AgentRunner(kind: .codex, model: "gpt-6.2-sol", effort: "low", timeout: .seconds(600))),
]

let companies = try DevNotes.companies(devFolder: devFolder, count: 4)
say(
    "judge probe, dev data only: \(companies.count) companies, \(families.count) writer families, \(families.count) judge families"
)

// 1. Notes.
var notes: [DevNotes.Note] = []
for company in companies {
    for family in families {
        if let note = try? await DevNotes.write(company, with: family) {
            notes.append(note)
        } else {
            say("note for \(company.name) by \(family.name) could not be written; left out")
        }
    }
}
say("notes written: \(notes.count)")

// 2. The variants of every note, made once, and then each judge family reads every note and every variant.
var variants: [(String, [DevNotes.Note])] = []
for variant in Variants.all(translator: families[0]) {
    var edited: [DevNotes.Note] = []
    for note in notes { edited.append(await variant.apply(note)) }
    variants.append((variant.name, edited))
}
let rubric = Rubric.research
for judgeFamily in families {
    let judge = RubricJudge(model: RecordedModel(judgeFamily.runner, store: store), rubric: rubric)
    var base: [ItemObservation] = []
    for note in notes { base += await observe(judge, note, runs: RubricJudge.runs) }
    say("\n== judge \(judgeFamily.name), base: \(notes.count) notes, \(rubric.items.count) items, 3 runs x 2 orders ==")
    say("order consistency (a call gives the same verdict in both orders): \(JudgeStability.orderConsistency(base))")
    say("single-call flip (a call differs from the majority of 3): \(JudgeStability.singleCallFlip(base))")
    say(
        "test-retest disagreement (3 runs, same order, not all equal), per item: \(JudgeStability.retestDisagreement(base))"
    )
    say("unknown only because orders or runs disagreed (ties): \(JudgeStability.tied(base))")
    say("pass rate by writer, same-family writer marked *:")
    for writerFamily in families {
        let own = base.filter { observation in
            notes.contains { $0.id == observation.note && $0.writer == writerFamily.name }
        }
        say(
            "  writer \(writerFamily.name)\(writerFamily.name == judgeFamily.name ? "*" : ""): \(JudgeStability.passRate(own))"
        )
    }
    for (name, edited) in variants {
        var changed: [ItemObservation] = []
        for note in edited { changed += await observe(judge, note, runs: 1) }
        let found = JudgeStability.change(from: base, to: changed)
        say(
            "variant \(name) (1 run x 2 orders): resolved verdict changed on \(found.changed); moved toward pass on \(found.towardPass)"
        )
    }
}
say("\nmodel calls that failed (counted as unknown votes): \(failedCalls)")
try report.joined(separator: "\n").write(to: reportFile, atomically: true, encoding: .utf8)

func observe(_ judge: RubricJudge, _ note: DevNotes.Note, runs: Int) async -> [ItemObservation] {
    let votes = await judge.votes(on: note.product, library: note.library, runs: runs)
    failedCalls += votes.flatMap { $0 }.filter { $0 == nil }.count
    return judge.rubric.items.map { item in
        ItemObservation(
            note: note.id, item: item.id,
            verdicts: votes.map { run in run.map { $0?[item.id]?.verdict ?? .unknown } })
    }
}
