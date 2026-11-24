import Foundation
import WorkbenchCore

/// The probe's numbers, every one labelled synthetic. Pure: it reads the saved day runs and the days.
struct Report {
    let days: [SyntheticDay]
    let results: [DayRun]
    let runs: Int
    let seed: UInt64
    let failures: [String]
    let spent: Double

    private func outcomes(_ arm: Arm, run: Int? = nil) -> [Outcome] {
        results.filter { run == nil || $0.run == run }.sorted { $0.day < $1.day }
            .flatMap { $0.outcomes(arm, on: days[$0.day]) }
    }

    func text() -> String {
        var lines = [
            "RECALL PROBE 1 — SYNTHETIC days only. Seed \(seed). Model ids from the run rows: "
                + Set(results.map(\.model)).sorted().joined(separator: ", ") + ".",
            "Days \(days.count), lines a day \(days.map(\.evidence.lines.count)), needles \(days.flatMap(\.needles).count);"
                + " day runs done \(results.count) of \(days.count * runs).",
        ]
        lines += recall() + noise() + gain() + slices() + confusions() + passes() + cost()
        lines += failures.map { "FAILED: \($0)" }
        return lines.joined(separator: "\n")
    }

    private func recall() -> [String] {
        ["", "Needle recall (synthetic), strict = cited line and kind; line = cited line, any kind:"]
            + Arm.allCases.flatMap { arm in
                (1...runs).map { run in
                    let found = outcomes(arm, run: run)
                    return
                        "  arm \(arm.rawValue) run \(run): strict \(share(found.filter(\.strict).count, of: found.count)),"
                        + " line \(share(found.filter(\.line).count, of: found.count))"
                }
            }
    }

    /// Needles whose strict result differs between run 1 and run 2 of one arm.
    private func noise() -> [String] {
        guard runs > 1 else { return [] }
        return ["", "Run-to-run noise (synthetic), needles whose result differs between run 1 and run 2:"]
            + Arm.allCases.map { arm in
                let pairs = zip(outcomes(arm, run: 1), outcomes(arm, run: 2))
                let strict = pairs.filter { $0.strict != $1.strict }.count
                let line = pairs.filter { $0.line != $1.line }.count
                return "  arm \(arm.rawValue): strict \(strict), line \(line)"
            }
    }

    /// Needles arm B finds that arm A of the same run missed. B holds all of A, so B never loses one.
    private func gain() -> [String] {
        ["", "Needles the gleaning pass added (synthetic, paired by run):"]
            + (1...runs).map { run in
                let rescued = zip(outcomes(.a, run: run), outcomes(.b, run: run)).filter { !$0.strict && $1.strict }
                let lineRescued = zip(outcomes(.a, run: run), outcomes(.b, run: run)).filter { !$0.line && $1.line }
                return "  run \(run): strict +\(rescued.count) \(rescued.map { "n\($0.0.needle.id)" }),"
                    + " line +\(lineRescued.count)"
            }
            + [
                "  arm A strict misses: "
                    + outcomes(.a).filter { !$0.strict }.map(\.needle.id).sorted().map { "n\($0)" }
                    .joined(separator: " ")
            ]
    }

    private func slices() -> [String] {
        func row<Key>(_ name: String, _ keys: [Key], _ key: (Needle) -> Key) -> [String]
        where
            Key: RawRepresentable,
            Key.RawValue == String, Key: Equatable
        {
            keys.map { value in
                let cells = Arm.allCases.map { arm in
                    let found = outcomes(arm).filter { key($0.needle) == value }
                    return "\(arm.rawValue) strict \(share(found.filter(\.strict).count, of: found.count)),"
                        + " line \(share(found.filter(\.line).count, of: found.count))"
                }
                return "  \(name) \(value.rawValue): " + cells.joined(separator: "; ")
            }
        }
        return ["", "By style and kind (synthetic, both runs pooled):"]
            + row("style", Needle.Style.allCases, \.style) + row("kind", Needle.Kind.allCases, \.kind)
    }

    /// Needles found on their line with another kind, in arm A.
    private func confusions() -> [String] {
        let wrong = outcomes(.a).filter { $0.line && !$0.strict }
        let counts = Dictionary(
            wrong.map { ("\($0.needle.kind.rawValue) -> \($0.kinds.joined(separator: "+"))", 1) }, uniquingKeysWith: +)
        return [
            "",
            "Arm A kind confusions on needle lines (synthetic): "
                + counts.sorted { $0.key < $1.key }.map { "\($0.key) x\($0.value)" }.joined(separator: ", "),
        ]
    }

    private func passes() -> [String] {
        let firstKept = results.flatMap(\.first)
        let gleaned = results.flatMap(\.gleaned)
        let needleLines = { (run: DayRun, items: [Kept]) in items.count - run.otherLines(items, on: days[run.day]) }
        func rules(_ drops: [String]) -> String {
            Dictionary(drops.map { ($0, 1) }, uniquingKeysWith: +).sorted { $0.key < $1.key }
                .map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        }
        let firstDrops = results.flatMap(\.firstDrops)
        let gleanDrops = results.flatMap(\.gleanDrops)
        return [
            "", "Passes (synthetic, all day runs; per day run = / \(results.count)):",
            "  pass 1: kept \(firstKept.count), on needle lines \(results.map { needleLines($0, $0.first) }.reduce(0, +)),"
                + " on other lines \(results.map { $0.otherLines($0.first, on: days[$0.day]) }.reduce(0, +));"
                + " drops \(firstDrops.count) [\(rules(firstDrops))]",
            "  gleaning: kept \(gleaned.count), on needle lines \(results.map { needleLines($0, $0.gleaned) }.reduce(0, +)),"
                + " on other lines \(results.map { $0.otherLines($0.gleaned, on: days[$0.day]) }.reduce(0, +));"
                + " near repeats (same line and kind as pass 1) \(results.map(\.nearRepeats).reduce(0, +));"
                + " drops \(gleanDrops.count) [\(rules(gleanDrops))]",
            "  background fact lines cited (code, line level): " + backgroundCited(),
            "  gleaning returned nothing kept on \(results.filter(\.gleaned.isEmpty).count) of \(results.count) day runs",
        ] + gleanedItems()
    }

    /// The background fact lines each arm's items cite, by run, out of all background lines of the days.
    private func backgroundCited() -> String {
        let total = days.map(\.background.count).reduce(0, +)
        let cells = Arm.allCases.flatMap { arm in
            (1...runs).map { run in
                let cited = results.filter { $0.run == run }.map { result in
                    Set(result.items(arm).map(\.line)).intersection(days[result.day].background).count
                }
                return "arm \(arm.rawValue) run \(run) \(share(cited.reduce(0, +), of: total))"
            }
        }
        return cells.joined(separator: "; ")
    }

    /// Every gleaned item, for reading by hand: needle or not, and its words.
    private func gleanedItems() -> [String] {
        results.sorted { ($0.day, $0.run) < ($1.day, $1.run) }.flatMap { run in
            run.gleaned.map { item in
                let day = days[run.day]
                let needle =
                    day.needles.first { $0.line == item.line }.map { "n\($0.needle.id)" }
                    ?? (day.background.contains(item.line) ? "background" : "other")
                return "    d\(run.day) r\(run.run) [\(item.line)] \(needle) \(item.kind) \(item.person): \(item.text)"
            }
        }
    }

    private func cost() -> [String] {
        func describe(_ usage: [Usage]) -> String {
            let total = usage.reduce(Usage(), +)
            let count = Double(max(usage.count, 1))
            return
                "mean \(dollars(total.costUSD / count)) a day run; tokens a day run: input \(Int(Double(total.inputTokens) / count)),"
                + " cache read \(Int(Double(total.cacheReadTokens) / count)), cache write"
                + " \(Int(Double(total.cacheWriteTokens) / count)), output \(Int(Double(total.outputTokens) / count))"
        }
        let first = results.map(\.firstUsage.costUSD).reduce(0, +)
        let glean = results.map(\.gleanUsage.costUSD).reduce(0, +)
        return [
            "", "Cost (synthetic days, list price from the run rows):",
            "  pass 1: " + describe(results.map(\.firstUsage)),
            "  gleaning: " + describe(results.map(\.gleanUsage)),
            "  gleaning adds \(String(format: "%.0f", first > 0 ? 100 * glean / first : 0))% to pass 1",
            "  spend in all run rows of this work folder: \(dollars(spent))",
        ]
    }
}
