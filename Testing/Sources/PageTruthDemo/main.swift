import AppKit
import CaptureService
import Foundation
import GRDB
import Kernel
import LocalSources
import PageSnapshot
import SwiftUI
import Synchronization

@testable import AgentCLI
@testable import WorkbenchCore
@testable import WorkbenchUI

/// Shows that a machine's page tells the truth, in both directions: a started machine gets its facts block, an
/// existing machine gets it once and never again after the person removed it, a job edit leaves the prompt as it
/// was, and the Add a team sheet makes the rows `Store.addTeam` makes. It draws the pages to PNGs off screen.
/// It uses scratch stores and no network, and never opens a window. Usage: page-truth [png-folder]

setvbuf(stdout, nil, _IOLBF, 0)
_ = NSApplication.shared
var failures = 0

func check(_ name: String, _ ok: Bool) {
    print("  \(ok ? "ok  " : "FAIL") \(name)")
    if !ok { failures += 1 }
}

func heading(_ text: String) { print("\n\(text)") }

struct Missing: Error {}

func need<Value>(_ value: Value?) throws -> Value {
    guard let value else { throw Missing() }
    return value
}

final class Scripted: StructuredModel, Sendable {
    let name = "scripted"

    func generate<T: Decodable & Sendable>(_ type: T.Type, schema: JSONSchema, instructions: String, input: String)
        async throws -> ModelAnswer<T>
    {
        ModelAnswer(
            value: try JSONDecoder().decode(T.self, from: Data(#"{"items":[]}"#.utf8)), model: name, usage: Usage(),
            reply: "")
    }
}

final class QuietNotifier: Notifier {
    func authorize() async -> SystemAccess { .allowed }
    func post(title: String, body: String, page: SidebarSelection) async throws {}
}

let shots = URL(
    filePath: CommandLine.arguments.dropFirst().first
        ?? "/Users/jeet/Projects/worktrace/plans/2026-11-24-page-truth/shots")
let scratch = FileManager.default.temporaryDirectory.appending(path: "page-truth-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: scratch) }
let owner = try PersonID("page-truth-owner")
let pipTemplate = try need(GalleryTemplate.of(id: MachineTemplate.team.id))

func freshStore(_ name: String) throws -> Store { try Store(directory: scratch.appending(path: name)) }

func count(_ store: Store, _ sql: String, _ arguments: StatementArguments = []) throws -> Int {
    try store.writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(sql)", arguments: arguments) ?? 0 }
}

func blockRows(_ store: Store, of machine: Machine) throws -> Int {
    try count(store, "machine_block WHERE object_id = ?", [machine.page])
}

func liveBlocks(_ store: Store, of machine: Machine) throws -> [MachineBlockID: MachineBlock] {
    try store.queries.page(of: try need(machine.page), for: PageViewer(owner: owner)).page.blocks
}

/// What an old store held: a machine with a page, and no row in `machine_block`.
func makeOldMachine(_ store: Store, of template: GalleryTemplate = pipTemplate) throws -> Machine {
    let machine = try need(try store.start(template).machine)
    let page = try need(machine.page)
    try store.writer.write { db in
        try db.execute(
            sql: "DELETE FROM container_order WHERE container = ?", arguments: [try Store.container(of: page)])
        try db.execute(sql: "DELETE FROM machine_block WHERE object_id = ?", arguments: [page])
    }
    return machine
}

func makeCrew(_ store: Store) throws -> Crew {
    Crew(
        store: store, capture: try CaptureService(store: store, owner: .success(owner)), founder: { "Rhea" },
        makeModel: nil, notifier: QuietNotifier(), owner: .success(owner),
        whatsAppContainer: scratch.appending(path: "no-whatsapp"))
}

// MARK: 1. Start

heading("1. A machine that starts has its template's facts block on its page")
let startStore = try freshStore("start")
let started = try need(try startStore.start(pipTemplate, name: "Pip").machine)
let startBlocks = try liveBlocks(startStore, of: started)
print("  Pip's page after start: \(startBlocks.values)")
check("start writes one live facts block", startBlocks.count == 1)
check(
    "it shows Pip's board of facts, by person",
    startBlocks.values.contains {
        if case .facts(let view) = $0 { view.layout == .board && view.groupBy == "person" } else { false }
    })
check(
    "it has no run and no proposal, as the person's own start",
    try count(startStore, "machine_block WHERE state = 'live' AND made_by_run IS NULL AND proposal_id IS NULL") == 1)
let crewStore = try freshStore("crew")
let crew = try makeCrew(crewStore)
let made = try need(crew.create(from: .followUps, name: "Follow-ups").flatMap { crew.helper(id: $0) })
check("Crew.create gives the same block", try liveBlocks(crewStore, of: made.machine).count == 1)

// MARK: 2. An existing machine

heading("2. A machine that exists with a page and no block gets its block once")
let oldStore = try freshStore("old")
let old = try makeOldMachine(oldStore)
check("before: the old page has 0 rows in machine_block", try blockRows(oldStore, of: old) == 0)
try oldStore.startPage(of: old)
check("the first load gives it one block", try liveBlocks(oldStore, of: old).count == 1)
try oldStore.startPage(of: old)
try oldStore.startPage(of: old)
check("a second and third load add nothing", try blockRows(oldStore, of: old) == 1)

heading("3. A block the person removed is not added again")
try oldStore.removeBlock(try need(try liveBlocks(oldStore, of: old).keys.first), surface: .machinePage)
check("the person removes it: 0 live blocks", try liveBlocks(oldStore, of: old).isEmpty)
try oldStore.startPage(of: old)
check("the next load adds none", try liveBlocks(oldStore, of: old).isEmpty)
check(
    "the marker is the removed row itself: 1 row, state removed",
    try count(oldStore, "machine_block WHERE state = 'removed'") == 1)

// MARK: 4. Job

heading("4. A job edit is one machine_change row and leaves the prompt as it was")
let jobStore = try freshStore("job")
let pip = try need(try jobStore.start(pipTemplate, name: "Pip").machine)
let changesBefore = try count(jobStore, "machine_change WHERE machine_id = ?", [pip.id])
let reader = { (machine: Machine) in HelperReader(spec: machine.spec, model: RecordedModel(Scripted(), store: jobStore))
}
check("before: the page shows the template's job", pip.job == pipTemplate.job)
try jobStore.edit(pip, job: "Keep my team's plans and blockers in view.")
let edited = try need(try jobStore.queries.machines().first { $0.id == pip.id })
check(
    "one new machine_change row",
    try count(jobStore, "machine_change WHERE machine_id = ?", [pip.id]) == changesBefore + 1)
check("the machine's own job shows", edited.job == "Keep my team's plans and blockers in view.")
check("the prompt is the same bytes", reader(pip).instructions == reader(edited).instructions)
check("the output schema is the same", reader(pip).schema == reader(edited).schema)
let sameSpec = { (machine: Machine) -> Machine in
    var plain = machine
    plain.spec.job = nil
    return plain
}
check("the spec is the same apart from the job", sameSpec(edited).spec == pip.spec)
try jobStore.edit(edited, job: "   ")
check(
    "a blank job gives the template's job back",
    try need(try jobStore.queries.machines().first { $0.id == pip.id }).job == pipTemplate.job)

// MARK: 5. Add a team

heading("5. The Add a team sheet makes the rows Store.addTeam makes")
func shape(_ store: Store) throws -> [String] {
    let objects = try store.queries.everyWorkObject().map { "\($0.kind):\($0.name)" }.sorted()
    let machines = try store.queries.machines().map { "\($0.template):\($0.name)" }.sorted()
    let rows = try ["machine", "machine_change", "machine_block", "work_object"].map { "\($0)=\(try count(store, $0))" }
    return objects + machines + rows
}
let coreStore = try freshStore("core")
let coreTeam = try coreStore.addTeam(.fund)
let sheetStore = try freshStore("sheet")
let sheetCrew = try makeCrew(sheetStore)
let sheetModel = TeamAddModel(crew: sheetCrew)
sheetModel.chosen = .fund
sheetModel.add()
print("  Fund started \(sheetModel.started?.machines ?? []), refused \(sheetModel.started?.refused ?? [])")
check("the sheet and the Core call make the same rows", try shape(coreStore) == shape(sheetStore))
check(
    "the sheet shows what the Core call returned",
    sheetModel.started?.machines == coreTeam.machines && sheetModel.started?.refused == coreTeam.refused)
check(
    "each started machine has its facts block",
    try count(sheetStore, "machine_block WHERE state = 'live'") == coreTeam.machines.count)
let blankStore = try freshStore("blank")
let blankModel = TeamAddModel(crew: try makeCrew(blankStore))
let blankBefore = try shape(blankStore)
blankModel.chosen = .blank
blankModel.add()
check(
    "Blank adds nothing and says so",
    try shape(blankStore) == blankBefore && blankModel.started?.folder == nil
        && blankModel.started?.items.isEmpty == true)

// MARK: 6. Pictures

heading("6. Pictures, drawn off screen into \(shots.path)")
let sizes = [("wide", CGSize(width: 1000, height: 900)), ("narrow", CGSize(width: 700, height: 900))]

func draw(_ view: some View, _ name: String) async throws {
    for (width, size) in sizes {
        for dark in [false, true] {
            print("  \(try await snapshot(view, named: "\(name)-\(width)", dark: dark, size: size, in: shots).path)")
        }
    }
}

let pipStore = try freshStore("pip")
let pipMachine = try need(try pipStore.start(pipTemplate, name: "Pip").machine)
/// Nine invented people with long names and long words, the shape of a team chat: a board must stay readable with them.
let people = [
    "Anantharaman Example", "Asha Example", "Benedikt Varga Example", "Chidi Example", "Dominika Kowalczyk Example",
    "Emeka Example", "Farida Example", "Giovanni Rossi Example", "Hyun-woo Park",
]
let words = [
    "the build is uploaded and the update has not reached the test tablet yet",
    "send the update to the second tablet before the review this afternoon",
    "this week we finish the shortcut work for every one of the system apps",
    "approve the branch so that the merge can happen before the evening",
    "check the serial numbers for the update test and send the list back",
    "four in the afternoon works, the notes will be shared after the class",
    "the pairing flow can start as soon as the signing key is available",
    "the weather app is free to take, the notes app is already taken",
    "use the corner table for the demo, the charger will be there",
]
let pipFacts = try await saveSyntheticFacts(
    in: pipStore, of: pipMachine, owner: owner, scope: "page-truth",
    sources: zip(people, words).map { "\($0): \($1)" }, quotes: words,
    fields: zip(people, words).map {
        ["person": $0, "project": "Update", "kind": "plan", "text": $1, "stance": "said", "asks": "team"]
    })
let pipCrew = try makeCrew(pipStore)
let pipHelper = try need(pipCrew.helper(id: pipMachine.id))
let pipPage = try need(pipHelper.pageModel)
let models = ModelSettings(store: pipStore, secrets: MemorySecrets())

func pageView(_ page: MachinePageModel, crew: Crew = pipCrew, helper: HelperModel = pipHelper) -> some View {
    Page(title: page.name, subtitle: "Team chats", rename: page.renaming { crew.rename(helper, to: $0) }) {
        MachinePageView(model: page)
    }
    .environment(crew).environment(models)
}

try pipStore.writer.write { db in
    try db.execute(sql: "DELETE FROM container_order")
    try db.execute(sql: "DELETE FROM machine_block")
}
pipPage.reload()
check(
    "before: Pip has \(pipFacts.count) facts and its page shows no block",
    pipPage.facts.count == pipFacts.count && pipPage.shown.blocks.isEmpty)
try await draw(pageView(pipPage), "1-pip-before")
let loaded = try MachinePageModel(
    helper: pipHelper, page: try need(pipMachine.page), store: pipStore, owner: owner,
    makeModel: { throw Missing() })
check("after: the page model that loads it gives it its facts view", loaded.shown.blocks.count == 1)
try await draw(pageView(loaded), "2-pip-after")
loaded.setEditing(.name, true)
try await draw(pageView(loaded), "3-pip-name-editing")
loaded.setEditing(.name, false)
loaded.setEditing(.job, true)
try await draw(pageView(loaded), "4-pip-job-editing")

let layouts = VStack(alignment: .leading, spacing: Space.l) {
    ForEach([FactsView.Layout.list, .table, .board, .counts], id: \.self) { layout in
        FactsBlockView(
            model: loaded,
            view: FactsView(
                title: layout.rawValue.capitalized, groupBy: layout == .table ? nil : "person", layout: layout,
                columns: ["person", "text", PageCatalog.quoteColumn]))
    }
}
.padding(Space.page).environment(pipCrew).environment(models)
try await draw(layouts, "7-layouts")

let mochiStore = try freshStore("mochi")
let mochiCrew = try makeCrew(mochiStore)
let oldBrief = """
    {"day":"\(WorkDay(containing: mochiStore.clock()).adding(days: -5))","headline":"Ask Asha for the signing key before the release slips.",
    "lines":[{"kind":"ask","basis":"seen","text":"Ravi waits on you for the signing key.","cites":[1]}],"unseen":[],"dropped":0}
    """
try StateKey<MorningBrief>.json("mochi.brief").save(
    try JSONDecoder().decode(MorningBrief.self, from: Data(oldBrief.utf8)), to: mochiStore)
let mochiHome = MochiPage()
    .environment(TodayModel(store: mochiStore, crew: mochiCrew)).environment(IdentityModel(store: mochiStore))
    .environment(MochiModel(store: mochiStore, crew: mochiCrew)).environment(
        ReviewModel(store: mochiStore, crew: mochiCrew)
    )
    .environment(mochiCrew)
try await draw(mochiHome, "5-mochi-old-brief")

try await draw(TeamSheet(model: sheetModel).environment(sheetCrew), "6-add-a-team-fund")

// MARK: 7. What a machine says of itself

heading("7. Pip as the founder's store holds it: paused by the plan limit, last reading made before the journal")
NSTimeZone.default = try need(TimeZone(identifier: "Asia/Kolkata"))

struct LimitReached: ClassifiedFailure {
    let failure = Run.Failure.limit
    let resetsAt: Date?
}

final class StoryClock: Sendable {
    private let moment: Mutex<Date>
    nonisolated init(_ start: Date) { moment = Mutex(start) }
    nonisolated var now: Date { moment.withLock { $0 } }
    nonisolated func move(to date: Date) { moment.withLock { $0 = date } }
}

func utc(_ text: String) throws -> Date { try need(try? Date(text, strategy: .iso8601)) }

let storyNow = try utc("2026-11-24T12:00:00Z")

/// Pip in a scratch store whose clock the story moves, with 85 synthetic facts in five days' worth, the schedule on
/// (hourly, 9 to 22), and the Claude terms confirmed.
func storyPip(_ name: String) async throws -> (store: Store, clock: StoryClock, crew: Crew, helper: HelperModel) {
    let clock = StoryClock(storyNow)
    let store = try Store(directory: scratch.appending(path: name), clock: { clock.now })
    let machine = try need(try store.start(pipTemplate, name: "Pip").machine)
    let sources = (1...85).map { "Asha: update number \($0) on the launch plan" }
    _ = try await saveSyntheticFacts(
        in: store, of: machine, owner: owner, scope: name, sources: sources,
        quotes: sources.map { _ in "on the launch plan" },
        fields: sources.indices.map { index in
            [
                "person": ["Asha", "Ravi", "Meera"][index % 3], "project": "Launch", "kind": "commitment",
                "text": "Update number \(index + 1) on the launch plan", "stance": "said", "asks": "team",
            ]
        })
    try store.saveState(
        String(decoding: try JSONEncoder().encode(WatchSchedule(isOn: true)), as: UTF8.self),
        forKey: WatchSchedule.stateKey(of: machine.task))
    try store.saveState(storyNow.ISO8601Format(), forKey: WatchSchedule.lastReadKey(of: machine.task))
    try MachineKey.chats(machine.task).save([WhatsAppChat(jid: "120363@g.us", name: "Team chat")], to: store)
    try store.confirmModelTerms()
    let crew = try makeCrew(store)
    return (store, clock, crew, try need(crew.helper(id: machine.id)))
}

func storyPage(_ pip: (store: Store, clock: StoryClock, crew: Crew, helper: HelperModel)) throws -> MachinePageModel {
    try MachinePageModel(
        helper: pip.helper, page: try need(pip.helper.machine.page), store: pip.store, owner: owner,
        status: { _ in pip.helper.status(at: storyNow) }, makeModel: { throw Missing() })
}

func sentence(_ helper: HelperModel) throws -> String { try helper.status(at: storyNow).get().sentence }

let founder = try await storyPip("founder-case")
let task = founder.helper.machine.task
founder.clock.move(to: try utc("2026-11-23T16:13:00Z"))
let finishedRun = try founder.store.beginRun(
    task: task, model: "synthetic", prompt: "none", input: "x", kinds: [.typed])
try founder.store.finishRun(finishedRun, model: "synthetic", usage: Usage(costUSD: 0.3), reply: "")
try founder.store.recordYield(of: finishedRun, kept: 12, dropped: 1)
founder.clock.move(to: try utc("2026-11-24T08:00:00Z"))
let limitedRun = try founder.store.beginRun(task: task, model: "synthetic", prompt: "none", input: "x", kinds: [.typed])
let pausedUntil = try utc("2026-11-25T09:00:00Z")
try founder.store.failRun(limitedRun, model: "synthetic", error: LimitReached(resetsAt: pausedUntil))
try founder.store.pauseModel(plan: "claude", until: pausedUntil)
founder.clock.move(to: storyNow)
let founderStatus = try founder.helper.status(at: storyNow).get()
let founderSentence = founderStatus.sentence
print("  the page says: \(founderSentence)")
check("the founder's case has no journal", founderStatus.latest == nil)
check(
    "it gives the pause, its end in India time, and the last model call, and no yield",
    founderSentence
        == "Pip is paused until 25 Nov, 2:30 PM: the Claude plan limit is reached. Pip's last model call was on 24 Nov at 1:30 PM, and it has no record of that reading."
)
check(
    "the plan pause is the only reason",
    founderStatus.notReading == [.model(.planLimit(plan: "claude", until: pausedUntil))])
check("the page seam shows what the helper says", try founder.helper.status(at: storyNow).get() == founderStatus)
check("85 facts are stored for Pip", try count(founder.store, "item WHERE task = ?", [task]) == 85)
try await draw(pageView(try storyPage(founder), crew: founder.crew, helper: founder.helper), "8-pip-status-limit")

heading("A healthy Pip in the middle of a reading")
let busy = try await storyPip("mid-reading")
let busyRun = try busy.store.beginRun(
    task: busy.helper.machine.task, model: "synthetic", prompt: "none", input: "x", kinds: [.typed])
try busy.store.writer.write { db in
    try Store.append(
        db,
        [
            .started(lines: 6, parts: 3, promptHash: "abc"), .partRead(number: 1, lines: 2, run: busyRun), .proposed(4),
            .kept(2), .dropped([.quoteNotInLines: 2]), .partRead(number: 2, lines: 2, run: busyRun), .proposed(3),
        ], to: busyRun, at: storyNow)
}
let busySentence = try sentence(busy.helper)
print("  the page says: \(busySentence)")
check("mid-reading says the part and what it found", busySentence.hasPrefix("Pip found 3 items in part 2 of 3."))
try await draw(pageView(try storyPage(busy), crew: busy.crew, helper: busy.helper), "8-pip-status-mid-reading")

heading("Pip with a finished journal, the fold open")
let done = try await storyPip("finished")
let doneRun = try done.store.beginRun(
    task: done.helper.machine.task, model: "synthetic", prompt: "none", input: "x", kinds: [.typed])
try done.store.finishRun(doneRun, model: "synthetic", usage: Usage(costUSD: 0.12), reply: "")
try done.store.writer.write { db in
    try Store.append(
        db,
        [
            .started(lines: 4, parts: 2, promptHash: "abc"), .partRead(number: 1, lines: 2, run: doneRun), .proposed(3),
            .kept(2), .dropped([.quoteNotInLines: 1]), .partRead(number: 2, lines: 2, run: doneRun), .proposed(1),
            .kept(1), .finished(RunCost(of: try Store.runs(db, of: done.helper.machine.task, from: doneRun))),
        ], to: doneRun, at: try utc("2026-11-24T11:00:00Z"))
}
let doneStatus = try done.helper.status(at: storyNow).get()
print("  the page says: \(doneStatus.sentence)")
for line in doneStatus.latest?.lines ?? [] { print("    \(line)") }
check("a finished journal lists one line for each event", doneStatus.latest?.lines.count == 9)
check(
    "its sentence names the schedule's next reading",
    doneStatus.sentence.hasSuffix("Its next reading is due on 24 Nov at 6:30 PM."))
try await draw(pageView(try storyPage(done), crew: done.crew, helper: done.helper), "8-pip-status-finished")
try await draw(
    MachineStatusView(isReading: false, shows: .journal(isOpen: true), read: { _ in .success(doneStatus) })
        .padding(Space.page).environment(done.crew).environment(models),
    "8-pip-status-fold-open")

print(failures == 0 ? "\nALL OK" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
