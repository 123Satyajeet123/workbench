import Evals
import Foundation

// Checks the prompt-injection corpus: schema, grammar, canaries, exits, synthetic targets, the split counts and the
// held-out digest, then plants one break per guard and checks that each is caught. Usage: inject-corpus [folder]; the
// default folder is Testing/InjectionCorpus. No model, no network.
let folder =
    CommandLine.arguments.dropFirst().first.map { URL(filePath: $0) }
    ?? URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "InjectionCorpus")
let (corpus, fileProblems) = try InjectionCorpus.load(folder)

func tally<Key: RawRepresentable>(_ keys: [Key]) -> String where Key.RawValue == String {
    Dictionary(grouping: keys.map(\.rawValue), by: { $0 }).sorted { $0.key < $1.key }
        .map { "\($0.key) \($0.value.count)" }.joined(separator: ", ")
}

let attacks = corpus.cases.filter { $0.kind == .attack }
print(
    "injection corpus: \(corpus.cases.count) cases (\(attacks.count) attack, \(corpus.cases.count - attacks.count) benign)"
)
print("by format: \(tally(corpus.cases.map(\.format)))")
print("attacks by goal: \(tally(attacks.map(\.goal)))")
print("attacks by technique: \(tally(attacks.map(\.technique)))")
print("by task: \(tally(corpus.cases.map(\.task.kind)))")
print("split (\(InjectionSplit.rule)): dev \(corpus.split(.dev).count), held_out \(corpus.split(.heldOut).count)")

let breaks = corpus.plantedBreaks
print("planted breaks caught: \(breaks.filter(\.caught).count) of \(breaks.count)")
let problems =
    fileProblems + corpus.problems + breaks.filter { !$0.caught }.map { "planted break not caught: \($0.name)" }
guard problems.isEmpty else {
    for problem in problems { print("problem: \(problem)") }
    print("FAILED: \(problems.count) problems")
    exit(1)
}
print("ALL OK")
