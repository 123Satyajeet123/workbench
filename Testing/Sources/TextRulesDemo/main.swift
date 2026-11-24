import Foundation
import SQLite3
import Synchronization

@testable import AgentCLI
@testable import WorkbenchCore

/// Shows the text rules of register item M10: the workspace profile that prompts render from, the prompts that stay
/// byte for byte what the old code wrote, and each removed word list or guess with what it matched before and after.
/// It uses scratch stores only, makes no network call and never opens the live store.

var failures = 0

func check(_ name: String, _ ok: Bool) {
    print("  \(ok ? "ok  " : "FAIL") \(name)")
    if !ok { failures += 1 }
}

func heading(_ text: String) { print("\n\(text)") }

final class Recorder: StructuredModel, Sendable {
    let name = "recorder"
    let last = Mutex(("", ""))

    func generate<T: Decodable & Sendable>(_ type: T.Type, schema: JSONSchema, instructions: String, input: String)
        async throws -> ModelAnswer<T>
    {
        last.withLock { $0 = (instructions, input) }
        let text = #"{"to":"","text":"hi"}"#
        return ModelAnswer(
            value: try JSONDecoder().decode(T.self, from: Data(text.utf8)), model: "r", usage: Usage(), reply: text)
    }
}

/// A model that answers every call with one fixed reply, as a model that decided in a known way.
final class Scripted: StructuredModel, Sendable {
    let name = "scripted"
    let reply: String

    init(_ reply: String) { self.reply = reply }

    func generate<T: Decodable & Sendable>(_ type: T.Type, schema: JSONSchema, instructions: String, input: String)
        async throws -> ModelAnswer<T>
    {
        ModelAnswer(
            value: try JSONDecoder().decode(T.self, from: Data(reply.utf8)), model: "s", usage: Usage(), reply: reply)
    }
}

let scratch = FileManager.default.temporaryDirectory.appending(path: "text-rules-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: scratch) }

func sql(_ statements: [String], in directory: URL) throws {
    var db: OpaquePointer?
    guard sqlite3_open(directory.appending(path: "workbench.sqlite").path, &db) == SQLITE_OK else {
        throw CocoaError(.fileReadUnknown)
    }
    defer { sqlite3_close(db) }
    for statement in statements where sqlite3_exec(db, statement, nil, nil, nil) != SQLITE_OK {
        throw CocoaError(.fileWriteUnknown)
    }
}

/// A store as the old code left it: a prompt row, and no profile key.
func oldStore(named name: String, withPrompt: Bool) throws -> URL {
    let directory = scratch.appending(path: name)
    _ = try Store(directory: directory)
    try sql(
        ["DELETE FROM state WHERE key = 'workspace.profile'"]
            + (withPrompt
                ? [
                    "INSERT INTO prompt(hash, task, instructions, schema, first_used) VALUES ('h','t','i','{}','2026-01-01')"
                ]
                : []),
        in: directory)
    return directory
}

// MARK: 1. The profile in the store

heading("1. The profile is a state key; a store gets it once, as it opens")
let fresh = try Store(directory: scratch.appending(path: "fresh"))
check("a new store starts with an empty profile", try fresh.queries.profile() == WorkspaceProfile())
let withPrompts = try Store(directory: try oldStore(named: "old-with-prompts", withPrompt: true))
check(
    "a store that holds prompts and no profile gets the continuity profile",
    try withPrompts.queries.profile() == .continuity)
let withoutPrompts = try Store(directory: try oldStore(named: "old-no-prompts", withPrompt: false))
check("a store with no profile and no prompts starts empty", try withoutPrompts.queries.profile() == WorkspaceProfile())
let custom = WorkspaceProfile(role: "engineer", occupation: "", languages: ["Tamil", "English"])
let customDirectory = scratch.appending(path: "custom")
try Store(directory: customDirectory).saveProfile(custom)
check(
    "a saved profile stays the same when the store opens again",
    try Store(directory: customDirectory).queries.profile() == custom)
print("  continuity profile: \(try Coding.json(WorkspaceProfile.continuity))")

// MARK: 2. Byte identity with the old code

heading("2. The migrated profile renders the bytes the old code wrote (fixtures: OldPrompts, run from 2ab076c5)")
let old = Dictionary(uniqueKeysWithValues: OldPrompts.all.map { ($0.name, $0.text) })
let continuity = WorkspaceProfile.continuity
let migratedModel = RecordedModel(Recorder(), store: withPrompts)

func same(_ name: String, _ new: String) {
    check("\(name.padding(toLength: 34, withPad: " ", startingAt: 0)) \(new.utf8.count) bytes", old[name] == new)
}
same("briefer", Briefer.instructions(for: continuity))
same("mochi", Mochi.instructions(for: continuity))
same("summarizer", Summarizer.instructions(for: continuity))
same("improver", Improver.instructions(for: continuity))
same("drafter", Drafter.instructions(for: continuity))
same("outboundQueries", OutboundQueries.instructions(for: continuity))
same("callNotes", CallSummarizer.instructions(for: continuity))
for descriptor in SourceRegistry.all {
    same("grammar.\(descriptor.key)", continuity.render(descriptor.grammar))
}
var specs = MachineTemplate.all.map { ($0.id, $0.spec) } + HelperSpec.withoutMachine.map { ($0.name, $0.spec) }
var withExamples = HelperSpec.timeline
withExamples.examples = 3
specs.append(("timeline+examples3", withExamples))
for (id, spec) in specs where id != MachineTemplate.newsSignals.id {
    same("reader.\(id)", HelperReader(spec: spec, model: migratedModel).instructions)
}
let oldCompanyMeaning = "Two companies can share a name: choose the one meant."
let newCompanyMeaning =
    "The article may name it in a shorter or longer form. Two companies can share a name or a first word: choose the one meant, and give no item for another company."
let newsNow = HelperReader(spec: .newsSignals, model: migratedModel).instructions
check(
    "reader.vc.news-signals differs from the old text in the company field only (its hash changes on purpose)",
    old["reader.vc.news-signals"]?.replacingOccurrences(of: oldCompanyMeaning, with: newCompanyMeaning) == newsNow
        && old["reader.vc.news-signals"] != newsNow)
let day = WorkDay(containing: Date(timeIntervalSince1970: 1_700_000_000))
var sample = Item(
    task: "t", day: day, scope: "", source: .whatsapp, citeFirst: 1, citeLast: 1, start: day.start, end: day.start,
    fields: ["task": "ship"], quote: "ship it", run: 1)
sample.state = .confirmed
same("readerExamples", HelperReader.examples([sample], spec: .timeline, profile: continuity))
let recorder = Recorder()
_ = try await Drafter(model: RecordedModel(recorder, store: withPrompts)).draft(
    sample, from: Machine(id: 1, name: "Pip", template: "t", spec: .timeline, state: .active), founder: "Asha")
same("drafterInput", recorder.last.withLock { $0.1 })
let call = AgentCall(
    prompt: "p", instructions: "rules", schemaText: "{}", model: "m", effort: "low", timeout: .seconds(1),
    dataOwner: continuity.render("{the role's}"))
check(
    "dataRule                           \(call.systemPrompt.utf8.count) bytes",
    call.systemPrompt == "rules\n\n" + (old["dataRule"] ?? ""))
print("  every fixture named: \(old.count) fixtures, all compared above")

heading("   Prompt hashes against the hashes PromptHashTests pinned before this change")
func hash<Task: ProfiledModelTask>(_: Task.Type) throws -> String {
    Digest.sha256(Task.instructions(for: continuity) + "\n" + (try Task.schema.jsonText))
}
let pinned: [(String, String, String)] = [
    ("Briefer", try hash(Briefer.self), "224c9d5c6e03fac5e261f70a7d5a22b2af53a84098bd767ad2e5445566757dd0"),
    ("Drafter", try hash(Drafter.self), "da7ac701fed90cd1089c38389a992c3ae5ae76b0fe7d718379caa9a7b6cde413"),
    ("Mochi", try hash(Mochi.self), "bc0221fc57dc722fca88dcf5ab86c2f600e92cd75e259dc7028f892416398b82"),
    ("Summarizer", try hash(Summarizer.self), "7747c46eb078acf8dbe9ca9578960c98152e31ee7081f56c47319f52bdd8ca43"),
    ("Improver", try hash(Improver.self), "5536115ac108de6b7c146b29ef9f7928ccf8c2e1237f0cf86fa0509eb276ed24"),
]
for (name, now, before) in pinned { check("\(name) \(now.prefix(12))", now == before) }

// MARK: 3. A new workspace

heading("3. A new workspace: the prompts say \"the person\" and name no language")
let newModel = RecordedModel(Recorder(), store: fresh)
let banned = #/(?i)founder|investor|Hindi|Hinglish|venture/#
let tasks: [(String, String)] = [
    ("briefer", Briefer.instructions(for: WorkspaceProfile())), ("mochi", Mochi.instructions(for: WorkspaceProfile())),
    ("summarizer", Summarizer.instructions(for: WorkspaceProfile())),
    ("improver", Improver.instructions(for: WorkspaceProfile())),
    ("drafter", Drafter.instructions(for: WorkspaceProfile())),
    ("outboundQueries", OutboundQueries.instructions(for: WorkspaceProfile())),
    ("callNotes", CallSummarizer.instructions(for: WorkspaceProfile())),
]
for (name, text) in tasks { check("\(name) has no persona or language word", text.firstMatch(of: banned) == nil) }
for descriptor in SourceRegistry.all {
    let text = WorkspaceProfile().render(descriptor.grammar)
    check(
        "grammar.\(descriptor.key) has none, and no token is left",
        text.firstMatch(of: banned) == nil && !text.contains("{"))
}
var neutral = HelperSpec.timeline
neutral.brief = "List what happened."
neutral.fields = [HelperSpec.Field("text", .text(required: true), meaning: "One short line.")]
neutral.title = "text"
neutral.badges = []
neutral.tones = [:]
neutral.examples = 3
neutral.criteria = HelperSpec.dealIntake.criteria
neutral.source = .whatsAppChat
let neutralText = HelperReader(spec: neutral, model: newModel).instructions
check(
    "a reader of a neutral spec has none either",
    neutralText.firstMatch(of: banned) == nil && !neutralText.contains("{"))
check(
    "  and it carries the examples rule and the criteria heading",
    neutralText.contains("items the person marked") && neutralText.contains("The person's criteria."))
print("  briefer, line 1:      \(Briefer.instructions(for: WorkspaceProfile()).split(separator: "\n")[0])")
print("  whatsapp grammar:     \(WorkspaceProfile().render(SourceDescriptor.whatsAppChat.grammar))")
print("  continuity grammar:   \(continuity.render(SourceDescriptor.whatsAppChat.grammar))")
check("an unknown {token} is left as written", WorkspaceProfile().render("{nothing}") == "{nothing}")
check("a role is not read again as a token", WorkspaceProfile(role: "{a role}").render("{the role}") == "the {a role}")
check("an engineer gets \"an\"", custom.render("{a role}") == "an engineer")
check(
    "one, two and three languages read as a list",
    [
        WorkspaceProfile(languages: ["Tamil"]).render("{language note}") == " People write in Tamil.",
        WorkspaceProfile(languages: ["Tamil", "English"]).render("{language note}")
            == " People write in Tamil and English.",
        continuity.render("{language note}") == " People write in Hindi, English and Hinglish.",
    ].allSatisfy { $0 })

// MARK: 4. B42, B43, B44: call source

heading("4. B42/B43: a call's title is the window's title as it is (old rows come from the old code)")
let newCalls = Behaviour.callLines()
var changed = 0
for (before, after) in zip(OldBehaviour.calls, newCalls) where before != after {
    changed += 1
    print("  was  \(before)\n  now  \(after)")
}
print("  \(newCalls.count - changed) of \(newCalls.count) rows are the same; \(changed) changed")
func serviceAndFlag(_ line: String) -> String {
    let result = line.components(separatedBy: " -> ")[1]
    return result.components(separatedBy: " · ")[0].components(separatedBy: " (call")[0] + result.suffix(7)
}
check(
    "service and the call flag are the same in every row",
    zip(OldBehaviour.calls, newCalls).allSatisfy { serviceAndFlag($0.0) == serviceAndFlag($0.1) })
heading("   B43 with calendar events: the title of the event whose join link is the call's address")
let withEvents = Behaviour.callLines(meetings: Behaviour.events)
for (before, after) in zip(newCalls, withEvents) where before != after { print("  event  \(after)") }
func title(_ line: String) -> String {
    let label = line.components(separatedBy: " -> ")[1].components(separatedBy: " (call")[0]
    return label.components(separatedBy: " · ").dropFirst().joined(separator: " · ")
}
let oldTitles = OldBehaviour.calls.map(title)
let eventTitles = Set(Behaviour.events.map(\.title))
let rawClean = zip(oldTitles, newCalls.map(title)).filter { $0 == $1 }.count
let withEventsClean = zip(oldTitles, withEvents.map(title)).filter { $0 == $1 || eventTitles.contains($1) }.count
print("  titles clean (the old cleaned title, or none): \(rawClean) of 13 without events")
print("  titles clean (the old cleaned title, none, or an event's own title): \(withEventsClean) of 13 with events")
print("  event titles used: \(withEvents.map(title).filter { eventTitles.contains($0) }.count) of 13")
check(
    "a link with another path is not the event",
    !MeetingLink.joins(
        URL(string: "https://meet.google.com/abc-defg-hij")!, address: "https://meet.google.com/zzz-zzzz-zzz"))
check(
    "scheme, query and a closing slash do not matter",
    MeetingLink.joins(URL(string: "https://zoom.us/j/123")!, address: "zoom.us/j/123/?pwd=x"))
check(
    "a call at another address keeps the raw window title",
    CallSource.identify(
        app: "zoom.us", bundleID: "us.zoom.xos", windowTitle: "Zoom Meeting - Q3", address: "https://zoom.us/j/9",
        meetings: Behaviour.events
    ).title == "Zoom Meeting - Q3")
print(
    "  no model call was added. No call exists when the window is seen, and the notes call has its own schema and hash."
)

heading("   B44: the site and app tables are data of the call descriptor")
let services = SourceDescriptor.callTranscript.callServices
check("the call descriptor holds 13 sites and 11 apps", services.sites.count == 13 && services.apps.count == 11)
check(
    "no other descriptor holds any",
    SourceRegistry.all.filter { $0.key != "call.transcript" }.allSatisfy {
        $0.callServices.sites.isEmpty && $0.callServices.apps.isEmpty
    })
check(
    "an invite link finds its service from the same table",
    MeetingLink.service(of: URL(string: "https://zoom.us/j/123")!) == "Zoom"
        && MeetingLink.service(of: URL(string: "https://meet.google.com/abc-defg-hij")!) == "Google Meet"
        && MeetingLink.service(of: URL(string: "https://example.com/j/1")!) == nil)

// MARK: 5. B45

heading("5. B45: settle, quiet and the ignored apps are a setting; the defaults are the old numbers, unmeasured")
let defaults = CallDetector.Settings()
check(
    "defaults: settle 5 s, quiet 15 s, five ignored bundle ids",
    defaults.settle == 5 && defaults.quiet == 15 && defaults.ignored.count == 5
        && defaults.ignored.contains("com.apple.VoiceMemos"))
func trace(_ settings: CallDetector.Settings) -> [CallDetector.Event] {
    var detector = CallDetector(settings: settings)
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let script: [(Set<String>, TimeInterval)] = [
        (["us.zoom.xos"], 0), (["us.zoom.xos"], 2), (["us.zoom.xos"], 6), ([], 10), (["us.zoom.xos"], 20), ([], 30),
        ([], 36),
    ]
    return script.flatMap { detector.update(listening: $0.0, at: start.addingTimeInterval($0.1)) }
}
check(
    "the default detector starts at 6 s and ends at 36 s, as the old test says",
    trace(defaults) == [.started("us.zoom.xos"), .ended("us.zoom.xos")])
var quick = defaults
quick.settle = 1
check("a setting of 1 s settle starts the call at 2 s", trace(quick).first == .started("us.zoom.xos"))
var strict = defaults
strict.ignored.insert("us.zoom.xos")
check("an app on the ignored list is never a call", trace(strict).isEmpty)
check("a store with no setting gives the defaults", try fresh.queries.callDetectorSettings() == defaults)
try fresh.saveCallDetectorSettings(quick)
check("a saved setting comes back", try fresh.queries.callDetectorSettings() == quick)

// MARK: 6. B46

heading("6. B46: bad news from a trusted feed is a mark of the spec, not two value tests in code")
func newsItem(_ polarity: String, trusted: String, extra: [String: String] = [:]) -> Item {
    Item(
        task: NewsSignals.task, day: day, scope: "", source: .web, citeFirst: 1, citeLast: 1, start: day.start,
        end: day.start, fields: ["polarity": polarity, NewsSignals.trustedField: trusted].merging(extra) { $1 },
        quote: "q",
        run: 1)
}
func listed(_ items: [Item], attention: HelperSpec.Attention = .builtIn) -> Int {
    var input = MorningInput(facts: [], me: "Asha")
    input.news = items
    input.attention = attention
    return MorningList.pick(input, now: day.start).first { $0.kind == .news }?.lines.count ?? 0
}
let marks = HelperSpec.Attention.builtIn.news
print("  marks of the built-in spec: \(marks.map { "\($0.field)=\($0.value)" })")
check("negative from a trusted feed is listed", listed([newsItem("negative", trusted: "yes")]) == 1)
check("negative from an untrusted feed is not", listed([newsItem("negative", trusted: "no")]) == 0)
check("positive from a trusted feed is not", listed([newsItem("positive", trusted: "yes")]) == 0)
check("neutral from an untrusted feed is not", listed([newsItem("neutral", trusted: "no")]) == 0)
check(
    "the marks name values of the spec's own enum",
    {
        guard
            case .choice(let polarities)? = HelperSpec.newsSignals.fields.first(where: { $0.name == "polarity" })?.kind
        else { return false }
        return polarities.contains(marks[0].value)
            && [NewsSignals.trusted, NewsSignals.untrusted].contains(marks[1].value)
    }())
var risk = HelperSpec.Attention()
risk.news = [.init("risk", "high")]
check(
    "a spec with other marks lists its own words",
    listed([newsItem("positive", trusted: "no", extra: ["risk": "high"])], attention: risk) == 1)
check("  and not the old words", listed([newsItem("negative", trusted: "yes")], attention: risk) == 0)
check(
    "a spec with no news marks lists no news",
    listed([newsItem("negative", trusted: "yes")], attention: HelperSpec.Attention()) == 0)

// MARK: 7. B47

heading("7. B47: company names compare by their words only; the legal-form and descriptor lists are gone")
func compare(_ before: [String], _ after: [String]) {
    var changed = 0
    for (was, now) in zip(before, after) where was != now {
        changed += 1
        print("  was  \(was)\n  now  \(now)")
    }
    print("  \(after.count - changed) of \(after.count) rows are the same; \(changed) changed")
}
compare(OldBehaviour.names, Behaviour.nameLines())
heading("   B47, news matching on the test fixtures")
compare(OldBehaviour.news, Behaviour.newsLines())

heading("   B47: the news reader names which offered company the article is about; code checks the answer")
let newsStore = try Store(directory: scratch.appending(path: "news"))
try newsStore.savePolicy(CapturePolicy(switches: [.web: true]))
func read(_ article: NewsArticle, among watched: [WatchedCompany], reply: String) async throws -> (
    offered: [String], kept: [String], dropped: Int
) {
    let offered = EntityMatcher.candidates(in: article, among: watched)
    let result = try await SignalReader(model: RecordedModel(Scripted(reply), store: newsStore)).read(
        article, candidates: offered)
    return (offered.map(\.label), result.items.map { $0[NewsSignals.idField] }, result.dropped)
}
func answer(_ company: String, quote: String) -> String {
    #"{"items":[{"company":"\#(company)","event":"layoff","polarity":"negative","date":"2026-09-19","cite":1,"quote":"\#(quote)"}]}"#
}
let layoff = Behaviour.article("Bolt Pay lays off 40", "The fintech Bolt Pay cut staff.")
let legal = Behaviour.company("Bolt Pay Private Limited")
let labs = Behaviour.company("Bolt Labs")
let one = try await read(
    layoff, among: [legal], reply: answer("Bolt Pay Private Limited", quote: "The fintech Bolt Pay cut staff."))
check("a legal name now matches its brand article: offered \(one.offered), kept \(one.kept)", one.kept == [legal.id])
let other = Behaviour.article("Bolt, the Estonian ride app, expands", "Bolt opened in Lagos.")
let none = try await read(other, among: [legal], reply: #"{"items":[]}"#)
check(
    "another Bolt: offered \(none.offered); a model that gives no item keeps nothing",
    none.offered == [legal.name] && none.kept.isEmpty)
let notOffered = try await read(other, among: [legal], reply: answer("Bolt Mobility", quote: "Bolt opened in Lagos."))
check(
    "  a company the prefilter did not offer is refused (dropped \(notOffered.dropped))",
    notOffered.kept.isEmpty && notOffered.dropped == 1)
let madeUp = try await read(
    other, among: [legal], reply: answer("Bolt Pay Private Limited", quote: "Bolt Pay fired 400 people."))
check(
    "  a quote that is not in the article is refused (dropped \(madeUp.dropped))",
    madeUp.kept.isEmpty && madeUp.dropped == 1)
let both = try await read(
    layoff, among: [legal, labs], reply: answer("Bolt Pay Private Limited", quote: "The fintech Bolt Pay cut staff."))
check(
    "two companies with the word Bolt: both offered \(both.offered); only the one named is kept",
    Set(both.offered) == [legal.name, labs.name] && both.kept == [legal.id])
let labsNews = Behaviour.article("Bolt Labs raises seed", "Bolt Labs closed a seed round.")
let labsOnly = try await read(
    labsNews, among: [legal, labs], reply: answer("Bolt Labs", quote: "Bolt Labs closed a seed round."))
check("  and the other article keeps the other company", labsOnly.kept == [labs.id])
print(
    "  not covered: a model that names an offered company with a real quote about another company. The gates cannot catch it; only a live model measures it."
)

// MARK: 8. B48

heading("8. B48: a guest's domain matches a deal only when the deal lists that domain")
compare(OldBehaviour.meetings, Behaviour.meetingLines())

print(failures == 0 ? "\nALL OK" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
