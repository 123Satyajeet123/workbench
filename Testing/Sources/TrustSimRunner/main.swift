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
    ("each item at chance \(AuditPolicy.pickChance) (now)", .eachItem(chance: AuditPolicy.pickChance)),
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
