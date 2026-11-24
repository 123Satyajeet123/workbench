import Foundation
import WorkbenchCore

/// The probe's numbers, every one labelled synthetic. Pure: it reads the saved passes and the days.
struct Report {
    let days: [SyntheticDay]
    let readings: [Reading]
    let seed: UInt64
    let failures: [String]
    let spent: Double

    private func reading(_ arm: Arm, day: Int, run: Int) -> Reading? {
        readings.first { $0.arm == arm && $0.day == day && $0.run == run }
    }

    /// The items an arm kept on a day: arm B is arm A's items and what its gleaning pass added.
    private func items(_ arm: Arm, day: Int, run: Int) -> [Kept]? {
        guard arm == .b else { return reading(arm, day: day, run: run)?.kept }
        guard let first = reading(.a, day: day, run: run), let added = reading(.b, day: day, run: run) else {
            return nil
        }
        return first.kept + added.kept
    }

    /// The (day, run) cells an arm has, in day order.
    private func cells(_ arm: Arm, run: Int? = nil) -> [(day: Int, run: Int)] {
        (1...2).filter { run == nil || $0 == run }.flatMap { run in
            days.indices.filter { items(arm, day: $0, run: run) != nil }.map { ($0, run) }
        }
    }

    private func outcomes(_ arm: Arm, in cells: [(day: Int, run: Int)]) -> [Outcome] {
        cells.flatMap { cell in
            days[cell.day].needles.map {
                Outcome($0.needle, line: $0.line, items: items(arm, day: cell.day, run: cell.run) ?? [])
            }
        }
    }

    private var runsDone: [(arm: Arm, run: Int)] {
        Arm.allCases.flatMap { arm in (1...2).filter { !cells(arm, run: $0).isEmpty }.map { (arm, $0) } }
    }

    func text() -> String {
        let models = Set(readings.map(\.model)).sorted().joined(separator: ", ")
        var lines = [
            "RECALL PROBE 2 — SYNTHETIC days only. Seed \(seed). Model ids from the run rows: \(models).",
            "Days \(days.count); lines \(days.map(\.evidence.lines.count)); characters \(days.map(\.characters));"
                + " needles \(days.flatMap(\.needles).count); fact lines \(days.map(\.factLines.count).reduce(0, +)).",
        ]
        lines += recall() + shapes() + paired() + noise() + factLines() + misses() + audit() + gleaning() + cost()
        return (lines + failures.map { "FAILED: \($0)" }).joined(separator: "\n")
    }

    private func recall() -> [String] {
        ["", "Needle recall (synthetic): strict = line and kind; line = line; person = strict and the right person."]
            + runsDone.map { arm, run in
                let cells = cells(arm, run: run)
                let found = outcomes(arm, in: cells)
                let founder = found.filter(\.needle.from.isFounder)
                let member = found.filter { !$0.needle.from.isFounder }
                return "  arm \(arm.rawValue) run \(run) (\(cells.count) days): strict"
                    + " \(share(found.filter(\.strict).count, of: found.count)), line"
                    + " \(share(found.filter(\.line).count, of: found.count)), person"
                    + " \(share(found.filter(\.personRight).count, of: found.count)); strict founder"
                    + " \(share(founder.filter(\.strict).count, of: founder.count)), member"
                    + " \(share(member.filter(\.strict).count, of: member.count))"
            }
    }

    private func shapes() -> [String] {
        func row(_ name: String, _ keep: (Needle) -> Bool) -> String {
            let cells = Arm.allCases.filter { !self.cells($0).isEmpty }.map { arm in
                let found = outcomes(arm, in: self.cells(arm)).filter { keep($0.needle) }
                return "\(arm.rawValue) \(share(found.filter(\.strict).count, of: found.count))"
                    + " (line \(found.filter(\.line).count))"
            }
            return "  \(name): " + cells.joined(separator: "; ")
        }
        return ["", "Strict recall by needle shape, kind and speaker (synthetic, all runs pooled):"]
            + Needle.Shape.allCases.map { shape in row(shape.rawValue) { $0.shape == shape } }
            + Needle.Kind.allCases.map { kind in row("kind \(kind.rawValue)") { $0.kind == kind } }
            + [row("long, founder") { $0.shape == .longSecond && $0.from.isFounder }]
            + [row("long, member") { $0.shape == .longSecond && !$0.from.isFounder }]
            + [row("reply, founder") { $0.shape == .reply && $0.from.isFounder }]
            + [row("reply, member") { $0.shape == .reply && !$0.from.isFounder }]
    }

    /// Arms C and D against arm A on the same days and run.
    private func paired() -> [String] {
        ["", "Arms C and D against arm A, paired by day and run (synthetic):"]
            + [Arm.c, .d].flatMap { arm in (1...2).map { (arm, $0) } }.compactMap { arm, run in
                let both = cells(.a, run: run).filter { cell in cells(arm, run: run).contains { $0 == cell } }
                guard !both.isEmpty else { return nil }
                let pairs = zip(outcomes(.a, in: both), outcomes(arm, in: both))
                let gained = pairs.filter { !$0.strict && $1.strict }.map(\.0.needle)
                let lost = pairs.filter { $0.strict && !$1.strict }.map(\.0.needle)
                let ids = { (needles: [Needle]) in needles.map { "n\($0.id)\($0.from.isFounder ? "F" : "M")" } }
                return "  \(arm.rawValue) run \(run) (\(both.count) days): gains \(gained.count) \(ids(gained)), loses"
                    + " \(lost.count) \(ids(lost))"
            }
    }

    private func noise() -> [String] {
        ["", "Run-to-run noise (synthetic), needles whose strict result differs between run 1 and run 2:"]
            + [Arm.a, .c].compactMap { arm in
                let both = cells(arm, run: 1).filter { cell in cells(arm, run: 2).contains { $0.day == cell.day } }
                guard !both.isEmpty else { return nil }
                let second = both.map { ($0.day, 2) }
                let differ = zip(outcomes(arm, in: both), outcomes(arm, in: second)).filter { $0.strict != $1.strict }
                return "  arm \(arm.rawValue) (\(both.count) days): \(differ.count) needles"
                    + " \(differ.map { "n\($0.0.needle.id)" })"
            }
    }

    /// Fact lines cited, from the labels of every line, and items kept on lines that hold no fact.
    private func factLines() -> [String] {
        ["", "Every line labelled (synthetic): fact lines cited by speaker; items on no-fact lines; Verifier drops:"]
            + runsDone.map { arm, run in
                var cited = [true: 0, false: 0]
                var facts = [true: 0, false: 0]
                var noFact = [true: 0, false: 0]
                var drops: [String] = []
                for cell in cells(arm, run: run) {
                    let day = days[cell.day]
                    let kept = items(arm, day: cell.day, run: cell.run) ?? []
                    let lines = Set(kept.map(\.line))
                    for (line, label) in day.labels where label.isFact {
                        facts[label.from.isFounder, default: 0] += 1
                        if lines.contains(line) { cited[label.from.isFounder, default: 0] += 1 }
                    }
                    for item in kept where day.labels[item.line]?.isFact == false {
                        noFact[day.labels[item.line]!.from.isFounder, default: 0] += 1
                    }
                    drops += reading(arm, day: cell.day, run: cell.run)?.drops ?? []
                }
                return "  arm \(arm.rawValue) run \(run): founder \(share(cited[true]!, of: facts[true]!)), member"
                    + " \(share(cited[false]!, of: facts[false]!)); items on no-fact lines founder \(noFact[true]!),"
                    + " member \(noFact[false]!); drops \(drops.count) \(Dictionary(drops.map { ($0, 1) }, uniquingKeysWith: +))"
            }
    }

    /// Every fact line an arm's run 1 did not cite, for reading by hand.
    private func misses() -> [String] {
        ["", "Fact lines not cited in run 1 (synthetic):"]
            + [Arm.a, .c, .d].flatMap { arm in
                cells(arm, run: 1).flatMap { cell in
                    let cited = Set((items(arm, day: cell.day, run: 1) ?? []).map(\.line))
                    return days[cell.day].evidence.lines.filter { line in
                        days[cell.day].labels[line.id]?.isFact == true && !cited.contains(line.id)
                    }.map { "  arm \(arm.rawValue) d\(cell.day) [\($0.id)] \($0.line.prefix(110))" }
                }
            }
    }

    /// The uncited-line audit, 2,000 draws, against the truth from the labels.
    private func audit() -> [String] {
        ["", "Uncited-line audit (synthetic labels answer the cards; 10 cards a day; 2,000 draws):"]
            + runsDone.map { arm, run in
                let uncited = cells(arm, run: run).map { cell in
                    let cited = Set((items(arm, day: cell.day, run: cell.run) ?? []).map(\.line))
                    return days[cell.day].evidence.lines.map(\.id).filter { !cited.contains($0) }
                        .map { days[cell.day].labels[$0]! }
                }
                let summary = Audit.summary(uncited: uncited, draws: 2_000, seed: seed)
                return "  arm \(arm.rawValue) run \(run): true missed fact lines \(summary.truth); estimate mean"
                    + " \(String(format: "%.1f", summary.mean)), 5-95% \(String(format: "%.1f", summary.low))-"
                    + "\(String(format: "%.1f", summary.high)); estimate 0 in"
                    + " \(String(format: "%.0f", 100 * summary.zeroShare))% of draws; \(summary.cardsPerDraw) cards a draw"
            }
    }

    private func gleaning() -> [String] {
        let passes = readings.filter { $0.arm == .b }
        guard !passes.isEmpty else { return ["", "Gleaning (arm B): not run."] }
        let added = passes.flatMap { pass in pass.kept.map { (pass.day, $0) } }
        let onFacts = added.filter { days[$0.0].labels[$0.1.line]?.isFact == true }.count
        return [
            "", "Gleaning pass on arm A run 1 (synthetic, \(passes.count) days):",
            "  kept \(added.count): on fact lines \(onFacts), on no-fact lines \(added.count - onFacts); drops"
                + " \(passes.flatMap(\.drops).count)",
        ]
    }

    private func cost() -> [String] {
        ["", "Cost (synthetic days, list price from the run rows):"]
            + Arm.allCases.compactMap { arm in
                let usage = readings.filter { $0.arm == arm }.map(\.usage)
                guard !usage.isEmpty else { return nil }
                let total = usage.reduce(Usage(), +)
                let count = Double(usage.count)
                return "  arm \(arm.rawValue): \(usage.count) passes, mean \(dollars(total.costUSD / count)); tokens a"
                    + " pass: cache read \(Int(Double(total.cacheReadTokens) / count)), cache write"
                    + " \(Int(Double(total.cacheWriteTokens) / count)), input \(Int(Double(total.inputTokens) / count)),"
                    + " output \(Int(Double(total.outputTokens) / count))"
            } + ["  spend in all run rows of this work folder: \(dollars(spent))"]
    }
}
