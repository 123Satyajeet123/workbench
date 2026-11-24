import Foundation
import Synchronization

@testable import AgentCLI
@testable import WorkbenchCore

/// Shows register item M11: every tuning number in one `RunSettings` value, the numbers a person may change saved in
/// the store, a cap that records what it left out, and prompts that keep their bytes. It uses scratch stores only,
/// makes no network call and never opens the live store.

var failures = 0

func check(_ name: String, _ ok: Bool) {
    print("  \(ok ? "ok  " : "FAIL") \(name)")
    if !ok { failures += 1 }
}

func heading(_ text: String) { print("\n\(text)") }

final class Scripted: StructuredModel, Sendable {
    let name = "scripted"
    let reply = #"{"items":[]}"#

    func generate<T: Decodable & Sendable>(_ type: T.Type, schema: JSONSchema, instructions: String, input: String)
        async throws -> ModelAnswer<T>
    {
        ModelAnswer(
            value: try JSONDecoder().decode(T.self, from: Data(reply.utf8)), model: name, usage: Usage(), reply: reply)
    }
}

let scratch = FileManager.default.temporaryDirectory.appending(path: "run-settings-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: scratch) }

// MARK: 1. The table

heading("1. The table: \(RunSettings.table.count) numbers")
func pad(_ text: String, _ width: Int) -> String { text.padding(toLength: width, withPad: " ", startingAt: 0) }
print("  \(pad("name", 28)) \(pad("default", 12)) \(pad("unit", 20)) \(pad("kind", 7)) \(pad("saved", 5)) measured on")
for row in RunSettings.table {
    print(
        "  \(pad(row.name, 28)) \(pad(row.value, 12)) \(pad(row.unit, 20)) \(pad(row.kind.rawValue, 7)) "
            + "\(pad(row.isSaved ? "yes" : "no", 5)) \(row.measuredOn)")
}
let measured = RunSettings.table.filter { $0.measuredOn != RunSettings.unmeasured }.map(\.name)
check(
    "only pickChance, delta and modelSearchUSD name a measurement: \(measured.joined(separator: ", "))",
    Set(measured) == ["pickChance", "delta", "modelSearchUSD"])
check(
    "every other number says \"\(RunSettings.unmeasured)\"",
    RunSettings.table.filter { !measured.contains($0.name) }.allSatisfy { $0.measuredOn == RunSettings.unmeasured })
check(
    "policy and bound numbers are never marked tuning",
    RunSettings.table.filter { $0.kind != .tuning }.map(\.name).contains("captureRetentionDays")
        && !RunSettings.table.filter { $0.kind == .tuning }.map(\.name).contains("captureRetentionDays"))

// MARK: 2. A saved value

heading("2. A saved value is read back")
let store = try Store(directory: scratch.appending(path: "settings"))
check("a new store reads the defaults", try store.queries.runSettings() == .standard)
var changed = RunSettings()
changed.pickChance = 0.2
changed.delta = 0.01
try store.saveRunSettings(changed)
let again = try Store(directory: scratch.appending(path: "settings")).queries.runSettings()
check("pickChance 0.2 and delta 0.01 are read back after the store opens again", again == changed)
print("  stored text: \(try store.queries.state(forKey: Store.runSettingsKey) ?? "none")")
let storedKeys = try JSONSerialization.jsonObject(
    with: Data((try store.queries.state(forKey: Store.runSettingsKey) ?? "{}").utf8))
check("a code default is not stored: the stored text names four numbers", (storedKeys as? [String: Any])?.count == 4)
var bad = RunSettings()
bad.confidence = 1.5
check("confidence 1.5 is refused", (try? store.saveRunSettings(bad)) == nil)
check("and the saved value is still the old one", try store.queries.runSettings() == changed)
let certificate = Certificate(
    answers: (0..<30).map { Certificate.Answer(wrong: false, chance: 0.2, run: Int64($0)) }, settings: changed)
let standardCertificate = Certificate(answers: certificate.answers)
check(
    "the certificate reads the settings it was given: chance 0.2 counts at pickChance 0.2 and not at 0.15's weights",
    certificate.status != standardCertificate.status)

// MARK: 3. A cap hit and a run under the cap

heading("3. A cap hit is recorded with its count; a run under the cap records nothing")
let now = Date(timeIntervalSince1970: 1_795_000_000)
let day = WorkDay(containing: now)
let grant = CapturePolicy(switches: [.whatsapp: true], allowList: [.whatsapp: ["team"]])
    .authorize(CaptureRequest(kind: .whatsapp, label: "team"), at: now).grant!
let spec = HelperSpec.team
guard let lifecycle = spec.lifecycle else { fatalError("the team machine has no lifecycle") }
let evidence = EvidenceSet(
    lines: [Evidence(id: 1, start: now, line: "Asha: hello", quotable: ["hello"])], context: ["members": ["Asha"]])

func fact(_ number: Int, run: RunID) -> Item {
    Item(
        task: spec.task, day: day, scope: "team", source: .whatsapp, citeFirst: 1, citeLast: 1, start: now, end: now,
        fields: [lifecycle.field: lifecycle.open[0], "text": "fact \(number)"], quote: "hello", run: run)
}

func scene(named name: String, facts: Int, deals: Int) async throws -> (Store, RunID) {
    let store = try Store(directory: scratch.appending(path: name), clock: { now })
    let seed = try await HelperReader(spec: spec, model: RecordedModel(Scripted(), store: store)).read(
        day: day, scope: "team", evidence: evidence)
    try store.saveReading(
        HelperReader.Result(items: (0..<facts).map { fact($0, run: seed.run!) }, dropped: 0, run: nil), of: spec,
        day: day, scope: "team", grant: grant)
    for number in 0..<deals {
        _ = try store.createWorkObject(type: ObjectTypes.deal, parent: nil, name: "Deal \(number)")
    }
    let reader = HelperReader(
        spec: spec, model: RecordedModel(Scripted(), store: store), objects: try store.queries.objectsToShow(for: spec))
    let result = try await reader.read(
        day: day, scope: "team", evidence: evidence, open: try store.queries.openItems(readBy: spec))
    return (store, result.run!)
}

let limits = RunSettings.standard
let (over, overRun) = try await scene(
    named: "over", facts: limits.openFactsShown + 5, deals: limits.objectsShownPerType + 3)
let cut = try over.queries.leftOut(of: overRun)
print("  over the caps: \(limits.openFactsShown + 5) open facts, \(limits.objectsShownPerType + 3) deals")
for entry in cut { print("    leftOut(of: run \(overRun)) -> \(entry.part.rawValue) \(entry.count)") }
check("5 open facts were left out", cut.contains(LeftOut(.openFacts, count: 5)))
check("3 objects were left out", cut.contains(LeftOut(.objects, count: 3)))
check(
    "the same rows are in the run's drop rows, rule left_out",
    try over.queries.dropReasons(of: overRun).allSatisfy { $0.rule == .leftOut })
let (under, underRun) = try await scene(named: "under", facts: 3, deals: 3)
check("under the caps: no count is recorded", try under.queries.leftOut(of: underRun).isEmpty)
check("under the caps: no drop row is written", try under.queries.dropReasons(of: underRun).isEmpty)
let kept = try over.queries.openItems(readBy: spec)
check(
    "the open facts shown are the newest \(limits.openFactsShown), and the count left out is on the value",
    kept.count == limits.openFactsShown && kept.leftOut == 5)

// MARK: 4. Prompt bytes

heading("4. Prompt bytes with the default settings against the base commit (fixtures: BasePrompts)")
let base = Dictionary(uniqueKeysWithValues: BasePrompts.all.map { ($0.name, $0.text) })
try over.saveProfile(.continuity)
let model = RecordedModel(Scripted(), store: over)
let continuity = WorkspaceProfile.continuity
var rendered: [(String, String)] = [
    ("briefer", Briefer.instructions(for: continuity)), ("mochi", Mochi.instructions(for: continuity)),
    ("summarizer", Summarizer.instructions(for: continuity)), ("improver", Improver.instructions(for: continuity)),
    ("drafter", Drafter.instructions(for: continuity)),
    ("outboundQueries", OutboundQueries.instructions(for: continuity)),
    ("callNotes", CallSummarizer.instructions(for: continuity)),
    ("claimQueries", ClaimChecker.queryInstructions), ("claimVerdict", ClaimChecker.verdictInstructions),
    ("asker", Asker.instructions),
]
for (id, spec) in MachineTemplate.all.map({ ($0.id, $0.spec) }) + HelperSpec.withoutMachine.map({ ($0.name, $0.spec) })
{
    rendered.append(("reader.\(id)", HelperReader(spec: spec, model: model).instructions))
}
for (name, text) in rendered { check("\(pad(name, 34)) \(text.utf8.count) bytes", base[name] == text) }
check("every fixture was compared: \(base.count) fixtures", Set(base.keys) == Set(rendered.map(\.0)))
let pinned: [(String, String, String)] = [
    (
        "Briefer", Digest.sha256(Briefer.instructions(for: continuity) + "\n" + (try Briefer.schema.jsonText)),
        "224c9d5c6e03fac5e261f70a7d5a22b2af53a84098bd767ad2e5445566757dd0"
    ),
    (
        "Drafter", Digest.sha256(Drafter.instructions(for: continuity) + "\n" + (try Drafter.schema.jsonText)),
        "da7ac701fed90cd1089c38389a992c3ae5ae76b0fe7d718379caa9a7b6cde413"
    ),
    (
        "Mochi", Digest.sha256(Mochi.instructions(for: continuity) + "\n" + (try Mochi.schema.jsonText)),
        "bc0221fc57dc722fca88dcf5ab86c2f600e92cd75e259dc7028f892416398b82"
    ),
    (
        "Summarizer", Digest.sha256(Summarizer.instructions(for: continuity) + "\n" + (try Summarizer.schema.jsonText)),
        "7747c46eb078acf8dbe9ca9578960c98152e31ee7081f56c47319f52bdd8ca43"
    ),
    (
        "Improver", Digest.sha256(Improver.instructions(for: continuity) + "\n" + (try Improver.schema.jsonText)),
        "5536115ac108de6b7c146b29ef9f7928ccf8c2e1237f0cf86fa0509eb276ed24"
    ),
    (
        "Asker", Digest.sha256(Asker.instructions + "\n" + (try Asker.schema.jsonText)),
        "f9f1b8580c7b66c819beb7e1bec2dc0af9d72ef124896878a89bbb785d7babcd"
    ),
]
for (name, hash, before) in pinned {
    check("PromptHashTests hash of \(name) \(hash.prefix(12)) is unchanged", hash == before)
}

print(failures == 0 ? "\nALL OK" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
