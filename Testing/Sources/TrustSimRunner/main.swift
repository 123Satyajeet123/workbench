import Evals
import Foundation
import WorkbenchCore

// Simulation of the trust certificate on synthetic audit answers. Usage: trust-sim. No store, no model, no network.
// Every number is a simulation, not a measurement on real marks.
let base = TrustSimulation()
let allowed = 0.10
print(
    "simulation: \(base.runs) runs per row, read after every answer, up to \(base.horizon) answers, seed \(base.seed)"
)

func percent(_ value: Double) -> String { String(format: "%5.1f%%", 100 * value) }
func answers(_ result: TrustSimulation.Result) -> String {
    result.median.map(String.init) ?? "> \(base.horizon)"
}

let populations: [(name: String, build: (Double) -> AuditPopulation)] = [
    ("equal chances (no weights needed)", { AuditPopulation.equal(size: 10, wrongRate: $0) }),
    ("mixed reading sizes, same wrong rate", { AuditPopulation.mixed(itemWrongRate: $0) }),
    ("mixed sizes, big readings worse", { AuditPopulation.bigReadingsWorse(itemWrongRate: $0) }),
    (
        "sizes up to 40, big readings worse",
        { AuditPopulation.bigReadingsWorse(itemWrongRate: $0, sizes: AuditPopulation.largeSizes) }
    ),
]
let policies: [(name: String, policy: PickPolicy)] = [
    ("one item per reading (before)", .onePerReading),
    (
        "each item at chance \(RunSettings.standard.pickChance) (now)",
        .eachItem(chance: RunSettings.standard.pickChance)
    ),
]
for (policyName, policy) in policies {
    var simulation = base
    simulation.policy = policy
    print("\n== pick policy: \(policyName)")
    for (name, build) in populations {
        print("\n\(name)")
        let heading = "false earned at 10%   median answers to earn at 0%, 2%, 5%"
        print("rule".padding(toLength: 24, withPad: " ", startingAt: 0) + heading)
        let atAllowed = simulation.run(build(allowed))
        let byRate = [0.0, 0.02, 0.05].map { simulation.run(build($0)) }
        for rule in TrustRule.allCases {
            let medians = byRate.map { answers($0[rule]!) }.joined(separator: ", ")
            print(
                rule.rawValue.padding(toLength: 24, withPad: " ", startingAt: 0)
                    + percent(atAllowed[rule]!.everEarned) + "              " + medians)
        }
    }
}

func cell(_ text: String, _ width: Int) -> String { text.padding(toLength: width, withPad: " ", startingAt: 0) }
func trimmed(_ value: Double) -> String { percent(value).trimmingCharacters(in: .whitespaces) }

func printCorrelatedRuns() {
    let simulation = CorrelatedRunSimulation()
    print(
        "\n== correlated runs: false certification at a true wrong rate of \(trimmed(allowed)); runs of size "
            + "\(CorrelatedRuns.sizes), each item picked at \(RunSettings.standard.pickChance), up to \(simulation.horizonSteps) "
            + "steps, \(simulation.trials) trials, bar at most \(trimmed(1 - RunSettings.standard.confidence))"
    )
    print(cell("concentration", 16) + StepRule.allCases.map { cell($0.rawValue, 40) }.joined())
    for concentration in [2.0, 10, 1000] {
        let shares = StepRule.allCases.map { simulation.falseEarned($0, concentration: concentration) }
        print(cell(String(Int(concentration)), 16) + shares.map { cell(percent($0), 40) }.joined())
    }
}

func quantile(_ values: [Int?], _ share: Double) -> String {
    let sorted = values.map { $0 ?? Int.max }.sorted()
    let value = sorted[min(sorted.count - 1, Int(share * Double(sorted.count)))]
    return value == Int.max ? "not in time" : String(value)
}

func printDrift(_ drift: DriftSimulation) {
    let result = drift.run()
    print(
        "\n== drift: wrong \(drift.wrongBefore) until earned, then \(drift.wrongAfter); concentration "
            + "\(Int(drift.concentration)), alarm bar 1/\(drift.delta), \(drift.trials) trials, "
            + "\(result.alarmRuns.count) earned, up to \(drift.horizonRuns) audited runs after the jump"
    )
    print(cell("detector", 24) + "median runs   90th percentile   not detected")
    for (name, runs) in [("drift alarm (e-CUSUM)", result.alarmRuns), ("plain certificate", result.certificateRuns)] {
        let missed = Double(runs.filter { $0 == nil }.count) / Double(runs.count)
        print(cell(name, 24) + cell(quantile(runs, 0.5), 14) + cell(quantile(runs, 0.9), 17) + percent(missed))
    }
    print(
        "false alarm while earning at \(drift.wrongBefore): \(percent(Double(result.falseAlarmsBeforeJump) / Double(drift.trials)))"
    )
    for rate in [0.05, 0.10] {
        let stable = drift.stable(wrongRate: rate)
        print(
            "stable \(rate), \(drift.horizonRuns) audited runs: drift alarm fires \(percent(stable.alarmed)); "
                + "earned certificate falls below its bar \(percent(stable.lostEarned))"
        )
    }
}

printCorrelatedRuns()
for concentration in [10.0, 1000] {
    for delta in [0.1, 0.01, RunSettings.standard.delta] {
        var drift = DriftSimulation()
        drift.concentration = concentration
        drift.delta = delta
        printDrift(drift)
    }
}
