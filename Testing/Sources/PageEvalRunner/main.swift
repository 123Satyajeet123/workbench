import AgentCLI
import Evals
import Foundation
import WorkbenchCore

@testable import WorkbenchUI

// The composer eval on a synthetic fixture. Every call goes through PageComposer, RecordedModel and AgentRunner, as the
// app makes it, on the person's own Claude plan. Every number is dev.
// The `tools` arm runs the Claude CLI over the read-only tool server `page-eval-tools`, built beside this tool.
// Usage: page-eval [--models sonnet,haiku] [--runs 3] [--parallel 3] [--cost-limit 2] [--total-cost-limit 12]
//                  [--arms one,tools] [--groups "vague request,large"] [--out file.json]
setvbuf(stdout, nil, _IOLBF, 0)

let defaultFolder = "/Users/jeet/Projects/worktrace/plans/2026-11-24-machine-page/eval"

func option(_ name: String) -> String? {
    CommandLine.arguments.firstIndex(of: name).flatMap { CommandLine.arguments[safe: $0 + 1] }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// A flag this tool does not know stops it before any model call: a run costs money on the person's plan.
let known: Set<String> = [
    "--models", "--runs", "--parallel", "--cost-limit", "--total-cost-limit", "--arms", "--groups", "--out",
]
let usage = """
    page-eval [--models sonnet,haiku] [--runs 3] [--parallel 3] [--cost-limit 2] [--total-cost-limit 12]
              [--arms one,tools] [--groups "vague request,large"] [--out file.json]
    """

func stop(_ reason: String) -> Never {
    print(usage)
    print("\(reason) Nothing was run.")
    exit(2)
}

let unknown = CommandLine.arguments.dropFirst().filter { $0.hasPrefix("-") && !known.contains($0) }
if !unknown.isEmpty { stop("Not known: \(unknown.joined(separator: " ")).") }

func list(_ name: String) -> [String]? { option(name).map { $0.split(separator: ",").map(String.init) } }

let armNames = list("--arms") ?? [PageEvalArm.one.rawValue]
let arms = armNames.compactMap { PageEvalArm(rawValue: $0) }
if arms.count != armNames.count { stop("Arm not known in \(armNames). Arms: \(PageEvalArm.allCases.map(\.rawValue)).") }
let groups = list("--groups")
let groupNames = Set(PageEvaluation.groupNames)
if let missing = groups?.first(where: { !groupNames.contains($0) }) {
    stop("Group not known: \(missing). Groups: \(PageEvaluation.groupNames.joined(separator: ", ")).")
}

func toolSetup() -> PageEvalToolSetup {
    guard let claude = AgentCLIKind.claude.installed() else { stop("The claude CLI is not installed.") }
    let server = Bundle.main.executableURL?.deletingLastPathComponent().appending(path: "page-eval-tools")
    guard let server, FileManager.default.isExecutableFile(atPath: server.path) else {
        stop("page-eval-tools is not built next to page-eval (swift build --product page-eval-tools).")
    }
    return PageEvalToolSetup(claude: claude, server: server)
}

let options = PageEvalOptions(
    models: (option("--models") ?? "sonnet,haiku").split(separator: ",").map(String.init),
    runs: option("--runs").flatMap { Int($0) } ?? 3, parallelism: option("--parallel").flatMap { Int($0) } ?? 3,
    costLimitUSD: option("--cost-limit").flatMap { Double($0) } ?? 2,
    totalCostLimitUSD: option("--total-cost-limit").flatMap { Double($0) } ?? 12, arms: arms, groups: groups,
    toolSetup: arms.contains(.tools) ? toolSetup() : nil)
let stampFormat = DateFormatter()
stampFormat.dateFormat = "yyyy-MM-dd-HHmmss"
let stamp = stampFormat.string(from: Date())
let output = URL(filePath: option("--out") ?? "\(defaultFolder)/\(stamp).json")

let result = try await PageEval.run(
    options,
    makeModel: { store, name in ModelChoice(kind: .claude, model: name).model(store: store, secrets: MemorySecrets()) },
    progress: { print($0) })
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
encoder.dateEncodingStrategy = .iso8601
try encoder.encode(result).write(to: output)
for summary in result.summaries { print("\n" + summary.text) }
print("\nwrote \(output.path)")
