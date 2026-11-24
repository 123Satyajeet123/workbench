import Foundation
import GRDB

@testable import WorkbenchCore

// Shows the gates of the one source registry twice: once where each holds, once where it lets the data through.
// One scratch store, no network. It never opens the live store.
//
//   swift run source-registry

nonisolated(unsafe) var failures = 0

func expect(_ claim: String, _ holds: Bool) {
    print("  \(holds ? "yes" : "NO ") \(claim)")
    if !holds { failures += 1 }
}

func heading(_ text: String) { print("\n\(text)") }

let directory = FileManager.default.temporaryDirectory.appending(path: "source-registry-demo-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: directory) }
let store = try Store(directory: directory)

// MARK: 1. Every descriptor and its fields

heading("1. Each descriptor and its fields")
for source in SourceRegistry.all {
    let needs = source.needs.map { "\($0)" }.joined(separator: ", ")
    let forgotten = source.forgets.activity.map { "activity.\($0.rawValue)" } + source.forgets.tables.map(\.name)
    let picker = source.picker.map { "\($0)" } ?? "none"
    print("  \(source.key) (spec \"\(source.specName)\")")
    print("    name \"\(source.name)\", origin \"\(source.origin)\", consent \(source.consent.rawValue)")
    print("    noun \(source.lineNoun), verb \"\(source.readVerb)\", picker \(picker)")
    print("    retention \(source.retention.rawValue), obtained \(source.obtainedBy.rawValue)")
    print("    allow-list \(source.requiresContainerAllowList), agreed audience \(source.requiresAgreedAudience)")
    print("    own writing \(source.ownWriting), follows companies \(source.followsCompanies)")
    print("    needs [\(needs)]")
    print("    forgets \(forgotten), page deny \(source.pageDenyHosts.sorted())")
}
expect("every key is unique", Set(SourceRegistry.all.map(\.key)).count == SourceRegistry.all.count)
expect("every spec name is unique", Set(SourceRegistry.all.map(\.specName)).count == SourceRegistry.all.count)
expect(
    "every consent kind has a descriptor, so every kind has a name",
    SourceKind.allCases.allSatisfy { SourceRegistry.descriptor(consent: $0) != nil })
expect(
    "the picker kinds come from the descriptors",
    GalleryTemplate.StartBlock.pickable == [.whatsapp, .mail, .screenText, .dropped, .telegram])
expect(
    "the kinds that need a named container come from the descriptors",
    Set(SourceKind.allCases.filter(SourceRegistry.requiresContainerAllowList)) == [.whatsapp, .telegram, .mail])

// MARK: 2. Health folded from needs

heading("2. Health from needs, each need both ways")
func inputs(
    consent: Bool = true, owner: Bool = true,
    permissions: Set<HealthNeed.MacPermission> = [.fullDiskAccess, .accessibility],
    keys: Set<HealthNeed.AppKey> = [.telegramApp], stale: [String] = [], browserOn: Bool = true
) -> SourceHealthInputs {
    var policy = CapturePolicy()
    for kind in SourceKind.captured { policy.switches[kind] = consent }
    let browser = BrowserHealth(
        id: "x.alpha", name: "Alpha", problem: browserOn ? nil : "Alpha is not enabled for Workbench.")
    return SourceHealthInputs(
        policy: policy, permissions: permissions, ownerKnown: owner, keys: keys, staleSites: stale, browsers: [browser])
}
func problems(_ source: SourceDescriptor, _ inputs: SourceHealthInputs) -> [SourceProblem] {
    SourceHealthModel.health(inputs).first { $0.source == source }?.problems ?? []
}
let mailSite = AdapterState.mailSite
let cases: [(String, SourceDescriptor, SourceHealthInputs, SourceProblem)] = [
    ("consent", .whatsAppChat, inputs(consent: false), .consentOff),
    ("owner", .gmailMail, inputs(owner: false), .ownerMissing),
    ("permission full disk", .whatsAppChat, inputs(permissions: [.accessibility]), .permissionMissing(.fullDiskAccess)),
    (
        "permission accessibility", .screenWindow, inputs(permissions: [.fullDiskAccess]),
        .permissionMissing(.accessibility)
    ),
    ("key", .telegramChat, inputs(keys: []), .keyMissing(.telegramApp)),
    ("browser", .webPage, inputs(browserOn: false), .browserNotReady("Alpha is not enabled for Workbench.")),
    ("reader current, mail site", .gmailMail, inputs(stale: [mailSite]), .siteStale(mailSite)),
    ("reader current, other site", .webPage, inputs(stale: ["Docs"]), .siteStale("Docs")),
]
for (name, source, broken, problem) in cases {
    expect("\(name): met, \(source.key) is ready", problems(source, inputs()).isEmpty)
    expect("\(name): not met, \(source.key) says \(problem)", problems(source, broken) == [problem])
}
expect(
    "a stale mail site does not stop pages, and a stale other site does not stop mail",
    problems(.webPage, inputs(stale: [mailSite])).isEmpty && problems(.gmailMail, inputs(stale: ["Docs"])).isEmpty)
expect(
    "the health list has one row for each source that declares needs, in registry order",
    SourceHealthModel.health(inputs()).map(\.source.key)
        == ["whatsapp.chat", "telegram.chat", "mail.gmail", "web.page", "screen.window"])

// MARK: 3. Forget hooks

heading("3. A delete of one kind erases that source's own tables and no other")
let old = "2020-01-01T00:00:00Z"
let current = "2030-01-01T00:00:00Z"
let hash = String(repeating: "a", count: 64)
func count(_ table: String, where condition: String = "1 = 1") -> Int {
    (try? store.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM \(table) WHERE \(condition)") }) ?? -1
}
func insertActivity(_ db: Database, kind: String, at time: String) throws {
    try db.execute(
        sql: """
            INSERT INTO activity(ts, kind, app, bundle_id, title, document, text)
            VALUES (?, ?, 'App', 'b', 't', NULL, ?)
            """, arguments: [time, kind, kind == "text" ? "x" : nil])
}
func seed() throws {
    try store.writer.write { db in
        for time in [old, current] {
            try db.execute(
                sql: """
                    INSERT INTO mail_part(
                        thread_id, message_id, kind, name, page, label, sender, subject, sent_at, seen_at, text)
                    VALUES ('t' || ?1, 'm' || ?1, 'message', '', 0, 'Deals', 'a', 's', ?1, ?1, 'text')
                    """, arguments: [time])
            try db.execute(
                sql: """
                    INSERT INTO news_article(feed, url, title, published_at, fetched_at, text)
                    VALUES ('f', 'https://news.example/' || ?1, 't', ?1, ?1, 'x')
                    """, arguments: [time])
            try db.execute(
                sql: """
                    INSERT INTO page_snapshot(url, fetched_at, content_hash, text)
                    VALUES ('https://page.example/' || ?1, ?1, ?2, 'x')
                    """, arguments: [time, hash])
            for kind in ["window", "file", "text"] { try insertActivity(db, kind: kind, at: time) }
        }
        for day in ["2020-01-01", "2030-01-01"] {
            try db.execute(
                sql: "INSERT INTO mail_open(thread_id, day, label) VALUES ('t', ?, 'Deals')", arguments: [day])
        }
        try db.execute(
            sql: """
                INSERT INTO recording(app, bundle_id, folder, started_at, ended_at, state)
                VALUES ('A', 'b', 'old-saved', ?1, ?1, 'saved'), ('A', 'b', 'now-recording', ?1, NULL, 'recording')
                """, arguments: [old])
    }
}
try seed()
let tables = ["mail_part", "mail_open", "news_article", "page_snapshot", "recording", "activity"]
print("  seeded: " + tables.map { "\($0) \(count($0))" }.joined(separator: ", "))
let cutoff = ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z")!

try store.delete(.kind(.mail, before: cutoff))
expect(
    "mail, before a cutoff: the old mail_part and mail_open go, the new stay",
    count("mail_part") == 1 && count("mail_open") == 1 && count("mail_open", where: "day = '2030-01-01'") == 1)
expect(
    "mail leaves news, page snapshots, recordings and activity alone",
    count("news_article") == 2 && count("page_snapshot") == 2 && count("recording") == 2 && count("activity") == 6)

try store.delete(.kind(.web, before: nil))
expect(
    "web: news_article and page_snapshot are empty, because two descriptors of kind web own one each",
    count("news_article") == 0 && count("page_snapshot") == 0)
expect("web leaves the mail rows that are left", count("mail_part") == 1)

try store.delete(.kind(.call, before: nil))
expect(
    "call: the saved recording goes, the one still recording stays",
    count("recording") == 1 && count("recording", where: "state = 'recording'") == 1)

try store.delete(.kind(.files, before: nil))
expect(
    "files: only the file rows of the capture log go",
    count("activity", where: "kind = 'file'") == 0 && count("activity") == 4)

try store.delete(.kind(.screenText, before: nil))
expect(
    "screen text: the text rows go, the window rows stay",
    count("activity", where: "kind = 'text'") == 0 && count("activity", where: "kind = 'window'") == 2)

try store.delete(.kind(.screen, before: nil))
expect("screen: the window rows go", count("activity") == 0)

try store.delete(.kind(.mail, before: nil))
expect("mail, no cutoff: all of it goes", count("mail_part") == 0 && count("mail_open") == 0)

// MARK: 4. Stored raw values decode

heading("4. Every stored raw source value decodes, and a spec writes the same value back")
let stored = [
    "whatsapp_chat", "telegram_chat", "screen_sessions", "page_text", "mail_threads", "news_articles", "web_search",
    "call_transcript",
]
for raw in stored {
    let json = Data("\"\(raw)\"".utf8)
    let decoded = try? JSONDecoder().decode(SourceDescriptor.self, from: json)
    let encoded = decoded.flatMap { try? JSONEncoder().encode($0) }
    print("  \(raw) -> \(decoded?.key ?? "nothing")")
    expect("\(raw) decodes and encodes to itself", decoded != nil && encoded == json)
}
expect(
    "a name no source has does not decode",
    (try? JSONDecoder().decode(SourceDescriptor.self, from: Data("\"nonsense\"".utf8))) == nil)
let template = MachineTemplate.team
let created = try store.createMachine(from: template.spec, template: template.id, name: "Pip")
let row =
    try store.writer.read {
        try String.fetchOne(
            $0, sql: "SELECT spec FROM machine_change WHERE machine_id = ?", arguments: [created.id])
    } ?? ""
expect(
    "a machine saved now has \"source\":\"whatsapp_chat\" in its machine_change row",
    row.contains("\"source\":\"whatsapp_chat\""))
let legacy = row.replacingOccurrences(of: "\"source\":\"whatsapp_chat\"", with: "\"source\":\"mail_threads\"")
let decodedSpec = try JSONDecoder().decode(HelperSpec.self, from: Data(legacy.utf8))
expect("a stored spec row with \"mail_threads\" decodes to the Gmail descriptor", decodedSpec.source == .gmailMail)

// MARK: 5. Deny list

heading("5. The deny list keeps LinkedIn, WhatsApp Web and Gmail out of page capture")
let neverKept = CapturePolicy.neverKeptHosts.sorted()
print("  never kept: \(neverKept)")
expect(
    "the deny list is the union of the descriptors' hosts",
    neverKept == ["linkedin.com", "mail.google.com", "web.whatsapp.com"])
var policy = CapturePolicy()
policy.switches[.screen] = true
policy.switches[.screenText] = true
policy.browsers["x.alpha"] = "Alpha"
let now = Date()
func page(_ address: String) -> WebPage {
    WebPage(browser: "x.alpha", url: address, title: "t", text: "some text on the page")
}
expect("a page of an ordinary site is kept", page("https://news.example/story").reading(policy: policy, at: now) != nil)
for host in ["https://www.linkedin.com/in/ada", "https://web.whatsapp.com/", "https://mail.google.com/mail/u/0/"] {
    expect("\(host) is not kept", page(host).reading(policy: policy, at: now) == nil)
}
var open = policy
open.switches[.web] = true
let gate = DriverGate(policy: open)
func refuses(_ address: String) -> Bool {
    gate.refusal(for: DriverRequest(url: URL(string: address)!), at: now) != nil
}
expect("the driver opens an ordinary site", !refuses("https://news.example/story"))
expect("the driver refuses linkedin.com", refuses("https://www.linkedin.com/in/ada"))

// MARK: 6. Container allow-list and own writing

heading("6. The container allow-list and own-writing rules come from the descriptors")
var chats = CapturePolicy(switches: [.whatsapp: true, .web: true])
let ask = CaptureRequest(kind: .whatsapp, label: "chat")
expect("whatsapp with no chat named is denied", chats.authorize(ask, at: now).grant == nil)
chats.allowList[.whatsapp] = ["chat"]
expect("whatsapp with the chat named is allowed", chats.authorize(ask, at: now).grant != nil)
expect("web needs no named container", chats.authorize(CaptureRequest(kind: .web), at: now).grant != nil)
chats.denyList[.note] = ["Secret"]
expect(
    "a note is written with its switch off, unless the project is on the deny list",
    chats.authorize(CaptureRequest(kind: .note, label: "Plan"), at: now).grant != nil
        && chats.authorize(CaptureRequest(kind: .note, label: "Secret"), at: now).grant == nil)

print(failures == 0 ? "\nALL OK" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
