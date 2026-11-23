import CoreML
import CryptoKit
import Evals
import Foundation
import WorkbenchCore

/// One set of pairs scored by every arm: a language and a premise form.
struct Condition {
    var name: String
    var pairs: [GroundingPair]
}

struct Arm {
    var name: String
    var scorer: any SupportScorer
}

/// The run of probe P-J1. It prints every number with its set (dev) and writes the same text to the report file.
final class Probe {
    let claims: [DevClaim]
    let devFolder: URL
    let pairs: [GroundingPair]
    let modelsFolder: URL
    let translations: [Translation.Language: [String: String]]
    let referenceFolder: URL
    let reportFile: URL
    private nonisolated(unsafe) var lines: [String] = []

    init(claims: [DevClaim], devFolder: URL, pairs: [GroundingPair], arguments: [String]) throws {
        self.claims = claims
        self.devFolder = devFolder
        self.pairs = pairs
        modelsFolder = URL(filePath: arguments[2])
        translations = try Translation.read(URL(filePath: arguments[3]))
        referenceFolder = URL(filePath: arguments[4])
        reportFile = URL(filePath: arguments[5])
    }

    func run() async throws {
        say("P-J1, dev data only. \(pairs.count) English pairs from \(claims.count) dev claims.")
        let conditions = makeConditions()
        for condition in conditions {
            let languages = Dictionary(grouping: condition.pairs) { ClaimLanguage($0.claim) }
            say(
                "\(condition.name): \(condition.pairs.count) pairs, \(condition.pairs.filter(\.supported).count) supported; "
                    + "ClaimLanguage: "
                    + ClaimLanguage.allCases.map { "\($0.rawValue) \(languages[$0]?.count ?? 0)" }.joined(
                        separator: ", "))
        }
        stageZero(conditions[0])
        var arms = [Arm(name: "lexical-overlap", scorer: LexicalOverlap())]
        for name in ["factcg", "minicheck"] {
            let clock = ContinuousClock()
            let started = clock.now
            let units: MLComputeUnits = name == "minicheck" ? .cpuOnly : .cpuAndGPU
            let scorer = try await CoreMLScorer.load(folder: modelsFolder.appending(path: name), computeUnits: units)
            say("cold load \(name): \(milliseconds(clock.now - started)) ms (identity \(scorer.identity.version))")
            arms.append(Arm(name: name, scorer: scorer))
        }
        var table: [String: [String: [Double]]] = [:]
        for arm in arms {
            for condition in conditions {
                table[arm.name, default: [:]][condition.name] = try await score(
                    arm, condition, record: condition.name == conditions[0].name)
            }
        }
        report(conditions: conditions, arms: arms, table: table)
        try await parity(arms: arms, scores: table, condition: conditions[0])
        try lines.joined(separator: "\n").write(to: reportFile, atomically: true, encoding: .utf8)
    }

    private func makeConditions() -> [Condition] {
        var conditions = [Condition(name: "english-quote", pairs: pairs)]
        let pages = GroundingPairs.withContext(pairs, claims: claims) { context(of: $0) }
        if pages.isEmpty {
            say("english-context: the dev folder has no cached page of a truth source (0 of \(claims.count)); not run")
        } else {
            conditions.append(Condition(name: "english-context", pairs: pages))
        }
        for language in Translation.Language.allCases {
            guard let table = translations[language] else { continue }
            let translated = pairs.map { pair in
                GroundingPair(
                    id: pair.id + "-" + language.rawValue, company: pair.company, kind: pair.kind,
                    claim: table[pair.claim] ?? pair.claim, premise: table[pair.premise] ?? pair.premise)
            }
            conditions.append(Condition(name: "\(language.rawValue)-quote", pairs: translated))
        }
        return conditions
    }

    /// The page around the quote of a claim, when the cache holds the page and the quote is in its text.
    private func context(of claim: DevClaim) -> String? {
        let name = Insecure.SHA1.hash(data: Data(claim.truthSourceUrl.utf8)).map { String(format: "%02x", $0) }.joined()
        guard let data = try? Data(contentsOf: devFolder.appending(path: "cache/\(name).txt")),
            let saved = try? JSONDecoder().decode([String: JSONValue].self, from: data),
            let body = saved["body"]?.string
        else { return nil }
        let text = HTMLText.plain(body)
        guard let span = text.nfc.span(of: claim.truthQuote) else { return nil }
        let scalars = Array(text.nfc.unicodeScalars)
        let window = scalars[max(0, span.lowerBound - 300)..<min(scalars.count, span.upperBound + 300)]
        return String(String.UnicodeScalarView(window))
    }

    /// Stage 0 on the English quote pairs: the share of each kind that code alone stops, and the false stops.
    private func stageZero(_ condition: Condition) {
        let verifier = Verifier(window: EvidenceSet(lines: []))
        let gate = DriverGate(policy: CapturePolicy())
        var stopped: [GroundingPair.Kind: (stopped: Int, total: Int)] = [:]
        for pair in condition.pairs {
            let source = Cite.Source.line(Data(repeating: 7, count: 32))
            let library = FixedCiteLibrary([SourceText(source: source, text: pair.premise, origin: .line)])
            let claim = ProductClaim(text: pair.claim, cites: [Cite(source: source, quote: pair.premise)])
            let outcome = verifier.structure(of: claim, subject: pair.company, library: library, gate: gate)
            var count = stopped[pair.kind] ?? (0, 0)
            count.total += 1
            if outcome.verdict == .fail { count.stopped += 1 }
            if pair.kind == .supported, outcome.verdict == .fail {
                say("  supported claim stopped (\(outcome.rule?.rawValue ?? "")): \(pair.claim) | \(outcome.detail)")
            }
            stopped[pair.kind] = count
        }
        say("stage 0 (code alone) on english-quote, dev:")
        for kind in GroundingPair.Kind.allCases {
            if let count = stopped[kind] { say("  \(kind.rawValue): \(count.stopped) of \(count.total) stopped") }
        }
    }

    private func score(_ arm: Arm, _ condition: Condition, record: Bool) async throws -> [Double] {
        var scores: [Double] = []
        var times: [Double] = []
        let clock = ContinuousClock()
        for (index, pair) in condition.pairs.enumerated() {
            let started = clock.now
            scores.append(try await arm.scorer.support(of: pair.claim, premise: pair.premise))
            if record && index > 0 { times.append(milliseconds(clock.now - started)) }
        }
        if record {
            let latency = Latency(milliseconds: times)
            say(
                "latency \(arm.name), warm, one pair at a time on this Mac: mean \(Int(latency.mean)) ms, p50 \(Int(latency.percentile(0.5))) ms, p95 \(Int(latency.percentile(0.95))) ms (n \(times.count))"
            )
        }
        return scores
    }

    private func report(conditions: [Condition], arms: [Arm], table: [String: [String: [Double]]]) {
        let companies = Array(Set(pairs.map(\.company)))
        for condition in conditions {
            say("\n== \(condition.name) (dev) ==")
            let control = scored(condition, table["lexical-overlap"]![condition.name]!)
            for arm in arms {
                let scores = table[arm.name]![condition.name]!
                let everything = scored(condition, scores)
                let kept =
                    arm.name == "lexical-overlap"
                    ? "control" : GroundingDecision.keeps(candidate: everything, control: control) ? "KEPT" : "dropped"
                say("\(arm.name): AUROC \(fmt(everything.auroc)) 90% \(interval(everything.interval90)) -> \(kept)")
                for kind in GroundingPair.Kind.allCases where kind != .supported {
                    let only = scored(condition, scores) { $0.kind == .supported || $0.kind == kind }
                    if only.unsupported.count > 0 {
                        say("    vs \(kind.rawValue) (\(only.unsupported.count)): AUROC \(fmt(only.auroc))")
                    }
                }
                bandReport(condition, scores, companies: companies)
            }
        }
    }

    /// The band from the choose half and what it does on the other half.
    private func bandReport(_ condition: Condition, _ scores: [Double], companies: [String]) {
        let choose = scored(condition, scores) { GroundingPairs.chooseHalf($0.company, among: companies) }
        let report = scored(condition, scores) { !GroundingPairs.chooseHalf($0.company, among: companies) }
        guard let band = choose.band else { return say("    band: too few pairs in the choose half") }
        let rates = report.rates(under: band)
        say(
            "    band from choose half \(band.version); report half (\(report.supported.count) supported, \(report.unsupported.count) unsupported): "
                + "false pass \(percent(rates.falsePass)), false fail \(percent(rates.falseFail)), unknown \(percent(rates.unknown))"
        )
    }

    private func scored(
        _ condition: Condition, _ scores: [Double],
        where keep: (GroundingPair) -> Bool = { _ in true }
    ) -> ScoredPairs {
        var result = ScoredPairs(supported: [], unsupported: [])
        for (pair, score) in zip(condition.pairs, scores) where keep(pair) {
            if pair.supported { result.supported.append(score) } else { result.unsupported.append(score) }
        }
        return result
    }

    /// Core ML against the reference implementation (token ids and probabilities) on the English quote pairs.
    private func parity(arms: [Arm], scores: [String: [String: [Double]]], condition: Condition) async throws {
        say("\n== parity with the reference tokenizer and torch float32 (english-quote, dev) ==")
        for arm in arms where arm.name != "lexical-overlap" {
            let file = referenceFolder.appending(path: "\(arm.name).json")
            guard let data = try? Data(contentsOf: file), let scorer = arm.scorer as? CoreMLScorer else {
                say("\(arm.name): no reference file")
                continue
            }
            let reference = try JSONDecoder().decode([Reference].self, from: data)
            var sameIDs = 0
            for (pair, expected) in zip(condition.pairs, reference) {
                if await scorer.tokenIDs(premise: pair.premise, claim: pair.claim) == expected.ids.map(Int32.init) {
                    sameIDs += 1
                }
            }
            let ours = scores[arm.name]![condition.name]!
            let largest = zip(ours, reference).map { abs($0 - $1.probability) }.max() ?? 0
            let flips = zip(ours, reference).filter { ($0 >= 0.5) != ($1.probability >= 0.5) }.count
            say(
                "\(arm.name): token ids equal on \(sameIDs) of \(reference.count) pairs; largest probability difference \(String(format: "%.4f", largest)); decision flips at 0.5: \(flips)"
            )
        }
    }

    struct Reference: Decodable {
        var ids: [Int]
        var probability: Double
    }

    private func say(_ line: String) {
        print(line)
        lines.append(line)
    }

    private func fmt(_ value: Double?) -> String { value.map { String(format: "%.3f", $0) } ?? "n/a" }
    private func interval(_ range: ClosedRange<Double>?) -> String {
        range.map { String(format: "%.3f-%.3f", $0.lowerBound, $0.upperBound) } ?? "n/a"
    }
    private func percent(_ value: Double) -> String { String(format: "%.0f%%", 100 * value) }
    private func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }
}
