import Foundation

// Probe R3: frozen-window scheduler (D4 as written) against claim-time-window scheduler (86 s5, U1).
// Synthetic store, fake runner, no model, no app store. Usage: scheduler-probe.
let scenario = Scenario()
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("scheduler-probe-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }

let policies = [Policy.frozen, Policy.claimTime, Policy.claimTimeNoCheck]
let results = try policies.map { try Simulation(policy: $0, scenario: scenario, directory: directory).run() }

let rows: [(String, (Metrics) -> String)] = [
    ("lines in two committed windows", { String($0.doubleReadLines) }),
    ("lines with two facts", { String($0.doubledFactLines) }),
    ("CLI starts after revoke (revoked source)", { String($0.startsAfterRevoke) }),
    ("rows waiting for revoked source at revoke", { String($0.waitingRowsAtRevoke) }),
    ("planned rows at wake (total / max per machine)", { "\($0.plannedRowsAtWakeTotal) / \($0.plannedRowsAtWakeMax)" }),
    ("runs started after wake (total / max per machine)", { "\($0.runsAfterWakeTotal) / \($0.runsAfterWakeMax)" }),
    ("max parallel children (global / one machine)", { "\($0.maxParallelChildren) / \($0.maxParallelSameMachine)" }),
    (
        "drain time after wake (simulated min)",
        { $0.drainMinutes.map { String(format: "%.1f", $0) } ?? "not drained in 24 h" }
    ),
    ("facts lost", { String($0.lostFacts) }),
    ("committed runs", { String($0.totalRuns) }),
    ("crashes fired (pl, ca, re, co)", { $0.crashesFired }),
]
let labelWidth = rows.map(\.0.count).max() ?? 0
print("seed \(Scenario.seed), \(Scenario.machines) machines, \(Scenario.sources) sources, cap K=\(Scenario.childCap)")
print("metric".padding(toLength: labelWidth, withPad: " ", startingAt: 0) + policies.map { "  | " + $0.name }.joined())
for (label, value) in rows {
    let cells = zip(policies, results).map { policy, metrics in
        "  | " + value(metrics).padding(toLength: policy.name.count, withPad: " ", startingAt: 0)
    }
    print(label.padding(toLength: labelWidth, withPad: " ", startingAt: 0) + cells.joined())
}

let c = results[1]
let control = results[2]
var failures: [String] = []
if c.doubleReadLines != 0 { failures.append("arm C double reads = \(c.doubleReadLines)") }
if c.doubledFactLines != 0 { failures.append("arm C doubled facts = \(c.doubledFactLines)") }
if c.startsAfterRevoke != 0 { failures.append("arm C starts after revoke = \(c.startsAfterRevoke)") }
if c.lostFacts != 0 { failures.append("arm C lost facts = \(c.lostFacts)") }
if c.drainMinutes == nil { failures.append("arm C did not drain") }
if c.waitingRowsAtRevoke == 0 { failures.append("revoke test is empty: no row was waiting") }
if control.startsAfterRevoke == 0 { failures.append("control did not start after revoke: the guard is untested") }
print(failures.isEmpty ? "ALL OK" : "FAIL: " + failures.joined(separator: "; "))
