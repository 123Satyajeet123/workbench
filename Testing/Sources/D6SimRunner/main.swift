import Evals
import Foundation
import WorkbenchCore

// The D6 simulations (research 86 Decision 7): P3, P4, P7, P9, P10, and the item-level step. Usage:
// d6-sim [p3|p4|p7|p9|p10|item]... (all when none). Synthetic and seeded: no store, no model, no network. Every number is a simulation, not a measurement.

func percent(_ value: Double) -> String { String(format: "%.1f%%", 100 * value) }
func cell(_ text: String, _ width: Int) -> String { text.padding(toLength: width, withPad: " ", startingAt: 0) }
func row(_ cells: [(String, Int)]) { print(cells.map { cell($0.0, $0.1) }.joined()) }
func days(_ value: Int?) -> String { value.map(String.init) ?? "-" }

let designs = [
    PickDesign("one chance 0.15 (today)", [Stratum(share: 1, chance: 0.15)]),
    PickDesign("0.15 / 1.0 (70/30)", [Stratum(share: 0.7, chance: 0.15), Stratum(share: 0.3, chance: 1)]),
    PickDesign("0.05 / 0.5 (80/20)", [Stratum(share: 0.8, chance: 0.05), Stratum(share: 0.2, chance: 0.5)]),
    PickDesign("0.02 / 1.0 (90/10)", [Stratum(share: 0.9, chance: 0.02), Stratum(share: 0.1, chance: 1)]),
]

func p3() {
    let simulation = WeightedAuditSimulation()
    let allowed = Certificate.allowedWrong
    print(
        "== P3 weighted e-process, unequal pick chances. seed \(simulation.seed), \(simulation.trials) trials, "
            + "read after every run; run sizes \(AuditPopulation.usualSizes.map(\.size)); bar e >= "
            + "\(Int(Certificate.threshold)) (at most \(percent(1 - Certificate.confidence)) false-earn allowed)")
    print("\nnull: item wrong rate \(percent(allowed)), 10 picks a day, \(simulation.horizonDays) days")
    row([("design", 25), ("wrong items", 40)] + AuditReading.allCases.map { ($0.rawValue, 11) })
    for design in designs {
        let cases: [(String, AuditPopulation, PickDesign, Double?)] =
            (design.strata.count == 1 ? [.even] : WrongPlacement.allCases).map {
                ($0.rawValue, .mixed(itemWrongRate: allowed), design.placing($0), nil)
            } + [
                ("big runs worse (item rate kept)", .bigReadingsWorse(itemWrongRate: allowed), design, nil),
                ("items of a run alike (Beta, 2)", .mixed(itemWrongRate: allowed), design, 2),
            ]
        for (name, population, placed, concentration) in cases {
            let result = simulation.run(placed, population: population, picksPerDay: 10, concentration: concentration)
            row(
                [(design.name, 25), (name, 40)] + AuditReading.allCases.map { (percent(result[$0]!.shareEarned()), 11) }
            )
        }
    }
    var power = simulation
    power.horizonDays = 120
    print(
        "\npower: same wrong rate in every stratum, \(power.horizonDays) days; median days / by day 14 / by 60; "
            + "rows: \(AuditReading.weighted.rawValue), \(AuditReading.runSum.rawValue)")
    row([("design", 25), ("wrong", 7), ("step", 10)] + [5, 10, 15].map { ("\($0) picks a day", 24) })
    for design in designs {
        for wrong in [0.02, 0.05] {
            let results = [5.0, 10, 15].map {
                power.run(design, population: .mixed(itemWrongRate: wrong), picksPerDay: $0)
            }
            for reading in [AuditReading.weighted, .runSum] {
                let cells = results.map { result in
                    let earned = result[reading]!
                    let summary = [
                        days(earned.medianDay), percent(earned.shareEarned(by: 14)),
                        percent(earned.shareEarned(by: 60)),
                    ]
                    return (summary.joined(separator: " / "), 24)
                }
                row([(design.name, 25), (percent(wrong), 7), (reading.rawValue, 10)] + cells)
            }
        }
    }
}

func p4() {
    let simulation = NonResponseSimulation()
    let design = designs[0]
    print(
        "\n== P4 non-response. seed \(simulation.seed), \(simulation.trials) trials, \(design.name), 10 picks a day, "
            + "\(simulation.horizonDays) days, expiry \(simulation.expiryDays) days, drift restarts on")
    let header = [("true wrong", 11), ("skip wrong", 11), ("skip right", 11)]
    print("\nfalse-earn (true rate at or above \(percent(Certificate.allowedWrong)))")
    row(header + NonResponseRule.allCases.map { ($0.rawValue, 22) })
    for wrong in [0.10, 0.12] {
        for (skipWrong, skipRight) in [(0.0, 0.0), (0.1, 0.1), (0.3, 0.0), (0.3, 0.1), (0.5, 0.1)] {
            let earned = simulation.run(
                design, population: .mixed(itemWrongRate: wrong), picksPerDay: 10, skipWrong: skipWrong,
                skipRight: skipRight)
            row(
                [(percent(wrong), 11), (percent(skipWrong), 11), (percent(skipRight), 11)]
                    + NonResponseRule.allCases.map { (percent(earned[$0]!.shareEarned()), 22) })
        }
    }
    print("\npower, skips at random: median days / earned by day 60")
    row(header + NonResponseRule.allCases.map { ($0.rawValue, 22) })
    for wrong in [0.02, 0.05] {
        for skip in [0.0, 0.02, 0.05, 0.10] {
            let earned = simulation.run(
                design, population: .mixed(itemWrongRate: wrong), picksPerDay: 10, skipWrong: skip, skipRight: skip)
            row(
                [(percent(wrong), 11), (percent(skip), 11), (percent(skip), 11)]
                    + NonResponseRule.allCases.map {
                        ("\(days(earned[$0]!.medianDay)) / \(percent(earned[$0]!.shareEarned(by: 60)))", 22)
                    })
        }
    }
}

func p7() {
    let base = NoiseBandSimulation()
    print(
        "\n== P7 A/A band. seed \(base.seed), \(base.trials) trials, \(base.days) trial days, \(base.marksPerDay) marks "
            + "a day (\(percent(base.rightShare)) right); a rule moves L stable right-marked facts; fail = above the band"
    )
    print("columns: share failed. diff = fact diff, lost = right-marked lost; emp = empirical, pf = per fact; ")
    print(
        "stable = fails when a right-marked fact moved that no re-run moved; band = empirical diff band P10-P90 (true P95)"
    )
    let settings: [(String, Int, Double)] = [
        ("R8 noise", 10, 0.5), ("R8 noise", 20, 0.5), ("R8 noise", 40, 0.5), ("calm (20% flaky)", 20, 0.2),
    ]
    for (noise, facts, flaky) in settings {
        var simulation = base
        simulation.factsPerDay = facts
        simulation.flakyShare = flaky
        print("\n\(noise), \(facts) facts a day")
        row(
            [("k", 4), ("null: diff emp/pf", 19), ("lost emp/pf", 14), ("stable", 8)]
                + [1, 3].map { ("L=\($0): lost emp/pf, stable", 30) } + [("band", 14)])
        for k in [2, 3, 5, 10, 20] {
            let runs = [0, 1, 3].map { simulation.run(reruns: k, rulesLost: $0) }
            let lost = { (result: NoiseBandSimulation.Result) in
                "\(percent(result.fails[.lost]![.empirical]!))/\(percent(result.fails[.lost]![.perFact]!))"
            }
            let null = runs[0]
            row(
                [
                    ("\(k)", 4),
                    (
                        "\(percent(null.fails[.factDiff]![.empirical]!))/\(percent(null.fails[.factDiff]![.perFact]!))",
                        19
                    ),
                    (lost(null), 14), (percent(null.stableLostFails), 8),
                ] + runs.dropFirst().map { ("\(lost($0)), \(percent($0.stableLostFails))", 30) }
                    + [("\(null.bandSpread.low)-\(null.bandSpread.high) (\(null.bandSpread.truth))", 14)])
        }
    }
}

func p9() {
    let scenarios: [(String, [Double])] = [("base", [0.04, 0.03, 0.005]), ("low", [0.015, 0.01, 0.002])]
    let layout: [(String, Double)] = [("a near cited", 0.15), ("c cue words", 0.10), ("d rest", 0.75)]
    let allocations = [[4, 3, 3], [2, 2, 6]]
    let base = RecallSimulation(strata: [])
    print(
        "\n== P9 recall estimate. seed \(base.seed), \(base.trials) trials, \(base.resamples) day resamples; "
            + "strata (share): \(layout.map { "\($0.0) \($0.1)" }.joined(separator: "; ")); cards a day (a, c, d) "
            + "\(allocations.map(\.description).joined(separator: " or ")); "
            + "\(base.factsPerDay) kept facts a day at precision \(base.precision), audit chance \(base.auditChance)")
    print("miss rates per line (a, c, d): \(scenarios.map { "\($0.0) \($0.1)" }.joined(separator: "; "))")
    row([
        ("miss", 6), ("cards", 8), ("lines/day", 10), ("days", 6), ("HT bias", 9), ("HT CV", 8), ("true R", 8),
        ("est R", 8),
        ("boot cover", 11), ("boot low", 9), ("ratio cover", 12), ("ratio bound", 11),
    ])
    for (name, rates) in scenarios {
        for cards in allocations {
            for lines in [50, 150, 400] {
                for window in [14, 30] {
                    var simulation = RecallSimulation(
                        strata: layout.indices.map {
                            .init(layout[$0].0, share: layout[$0].1, missRate: rates[$0], cards: cards[$0])
                        })
                    simulation.linesPerDay = lines
                    simulation.days = window
                    let result = simulation.run()
                    row([
                        (name, 6), (cards.map(String.init).joined(separator: ","), 8), ("\(lines)", 10),
                        ("\(window)", 6), (percent(result.missedBias), 9),
                        (percent(result.missedCV), 8), (String(format: "%.3f", result.meanTrueRecall), 8),
                        (String(format: "%.3f", result.meanEstimatedRecall), 8),
                        (percent(result.bootstrapCoverage), 11),
                        (String(format: "%.3f", result.medianBootstrapLow), 9),
                        (percent(result.ratioBoundCoverage), 12),
                        (String(format: "%.3f", result.medianRatioBound), 11),
                    ])
                }
            }
        }
    }
}

func p10() {
    let cost = CertificateCost()
    print(
        "\n== P10 read cost. seed \(cost.seed), \(cost.answersPerRun) answers a run at chance \(AuditPolicy.pickChance); "
            + "replay = Certificate.status, median of 5 reads; kept = add one run and read, mean of the last 1,000 runs"
    )
    row([("runs", 9), ("wrong", 7), ("replay read", 14), ("status", 22), ("kept read", 12), ("kept bound", 10)])
    for runs in [10_000, 100_000] {
        for wrong in [0.03, 0.10] {
            let answers = cost.answers(runs: runs, wrongRate: wrong)
            let (replay, status) = cost.replayRead(answers)
            let (kept, bound) = cost.keptRead(answers)
            let shown =
                switch status {
                case .earned(let bound): String(format: "earned %.4f", bound)
                case .needsMore(let more): "needs \(more) more"
                }
            row([
                ("\(runs)", 9), (percent(wrong), 7), (replay.formatted(.units(allowed: [.milliseconds])), 14),
                (shown, 22), (kept.formatted(.units(allowed: [.microseconds], fractionalPart: .show(length: 1))), 12),
                (bound.map { String(format: "%.3f", $0) } ?? "-", 10),
            ])
        }
    }
}

func item() {
    var simulation = ItemLevelSimulation()
    let allowed = Certificate.allowedWrong
    print(
        "\n== Item-level step. seed \(simulation.seed), \(simulation.trials) trials, read after every run; draw order, "
            + "expired (\(simulation.expiryDays) days) = wrong in every step; bar e >= \(Int(Certificate.threshold))")
    print(
        "\nnull, \(simulation.horizonDays) days, 10 picks a day. Cell = false-earn against the model rate / against the "
            + "facts drawn so far (design-based)")
    row([("design", 25), ("wrong items", 34)] + ItemStep.allCases.map { ($0.rawValue, 14) })
    let show = { (design: PickDesign, name: String, result: [ItemStep: ItemStepOutcome]) in
        row(
            [(design.name, 25), (name, 34)]
                + ItemStep.allCases.map {
                    ("\(percent(result[$0]!.firstEarned.shareEarned())) / \(percent(result[$0]!.designFalseEarn))", 14)
                })
    }
    for design in designs {
        let cases: [(String, AuditPopulation, PickDesign, Double?)] =
            (design.strata.count == 1 ? [.even] : WrongPlacement.allCases).map {
                ($0.rawValue, .mixed(itemWrongRate: allowed), design.placing($0), nil)
            } + [
                ("big runs worse", .bigReadingsWorse(itemWrongRate: allowed), design, nil),
                ("items of a run alike (Beta 2)", .mixed(itemWrongRate: allowed), design, 2),
                ("big runs worse + alike (Beta 2)", .bigReadingsWorse(itemWrongRate: allowed), design, 2),
            ]
        for (name, population, placed, concentration) in cases {
            show(
                design, name,
                simulation.run(placed, population: population, picksPerDay: 10, concentration: concentration))
        }
    }
    let skipped = simulation.run(
        designs[0], population: .mixed(itemWrongRate: allowed), picksPerDay: 10, skipWrong: 0.3, skipRight: 0)
    show(designs[0], "30% of wrong picks never answered", skipped)
    let margin = simulation.run(designs[0], population: .bigReadingsWorse(itemWrongRate: 0.12), picksPerDay: 10)
    show(designs[0], "big runs worse, item rate 12%", margin)

    simulation.horizonDays = 120
    print(
        "\npower, same rate in every stratum, \(simulation.horizonDays) days. Cell = median days at 5 / 10 / 15 picks a day"
    )
    row([("design", 25), ("wrong", 7), ("skips", 7)] + ItemStep.allCases.map { ($0.rawValue, 14) })
    for design in designs {
        for (wrong, skip) in [(0.02, 0.0), (0.05, 0.0), (0.05, 0.02)] where skip == 0 || design.strata.count == 1 {
            let results = [5.0, 10, 15].map {
                simulation.run(
                    design, population: .mixed(itemWrongRate: wrong), picksPerDay: $0, skipWrong: skip, skipRight: skip)
            }
            row(
                [(design.name, 25), (percent(wrong), 7), (percent(skip), 7)]
                    + ItemStep.allCases.map { step in
                        (results.map { days($0[step]!.firstEarned.medianDay) }.joined(separator: " / "), 14)
                    })
        }
    }
}

let probes: [String: () -> Void] = ["p3": p3, "p4": p4, "p7": p7, "p9": p9, "p10": p10, "item": item]
let asked = CommandLine.arguments.dropFirst()
for name in asked.isEmpty ? ["p3", "p4", "p7", "p9", "p10", "item"] : Array(asked) {
    guard let probe = probes[name] else {
        print("unknown probe \(name); use \(probes.keys.sorted().joined(separator: ", "))")
        exit(1)
    }
    probe()
}
