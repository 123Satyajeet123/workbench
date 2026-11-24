import Foundation
import GRDB

@testable import WorkbenchCore

/// Shows that a team template starts inside an existing workspace, beside the teams already there, in both directions:
/// the rows before stay as they were, a second add makes a second team, each deal is read by the machines of its own
/// team, Today reads both teams, Blank adds nothing, and a refused item leaves the rest of the team started. It uses
/// scratch stores and no network.

var failures = 0

struct Missing: Error {}

func need<Value>(_ value: Value?) throws -> Value {
    guard let value else { throw Missing() }
    return value
}

@MainActor func check(_ name: String, _ ok: Bool) {
    print("  \(ok ? "yes" : "NO"): \(name)")
    if !ok { failures += 1 }
}

let scratch = FileManager.default.temporaryDirectory.appending(path: "add-team-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: scratch) }

func freshStore(_ name: String) throws -> Store { try Store(directory: scratch.appending(path: name)) }

struct Rows: Equatable {
    var objects: [WorkObject]
    var machines: [Machine]

    init(_ store: Store) throws {
        objects = try store.queries.everyWorkObject()
        machines = try store.queries.machines()
    }

    /// Whether every row of `earlier` is in these rows, with the same values.
    func keeps(_ earlier: Rows) -> Bool {
        earlier.objects.allSatisfy { objects.contains($0) } && earlier.machines.allSatisfy { machines.contains($0) }
    }
}

func children(_ store: Store, of folder: WorkObjectID?) throws -> [WorkObject] {
    try store.queries.workObjects(parent: folder, includeArchived: false)
}

func child(_ store: Store, _ name: String, of folder: WorkObjectID?) throws -> WorkObject {
    try children(store, of: folder).first { $0.name == name }!
}

func machinesBelow(_ store: Store, _ team: WorkObject) throws -> [Machine] {
    let tree = try store.queries.folderTree()
    return try store.queries.machines().filter { tree.team(of: $0.folder) == team.id }
}

/// The workspace as it is made today: each item of the template at the root, with no team folder.
func startAtRoot(_ store: Store, _ template: TeamTemplate) throws {
    for item in template.items { try store.start(item) }
}

print("1. Fund added to a workspace that already runs the Startup team")
let workspace = try freshStore("workspace")
try startAtRoot(workspace, .startupTeam)
let before = try Rows(workspace)
print("  before: root folders \(try children(workspace, of: nil).map(\.name)), machines \(before.machines.map(\.name))")
let fund = try workspace.addTeam(.fund)
let after = try Rows(workspace)
let added = after.objects.filter { object in !before.objects.contains { $0.id == object.id } }
let fundFolder = try child(workspace, "Fund", of: nil)
print("  after: root folders \(try children(workspace, of: nil).map(\.name))")
print("  Fund folder holds \(try children(workspace, of: fundFolder.id).map(\.name))")
check("every folder, page and machine from before is unchanged", after.keeps(before))
check("the team folder is the new root and the result names it", fund.folder?.id == fundFolder.id)
let machinesBelowFund = try machinesBelow(workspace, fundFolder)
check(
    "the new machines are exactly the machines under the Fund folder",
    Set(after.machines.map(\.id)).subtracting(before.machines.map(\.id)) == Set(machinesBelowFund.map(\.id)))
let workspaceTree = try workspace.queries.folderTree()
check(
    "every new object is the Fund folder or sits below it",
    added.allSatisfy { $0.id == fundFolder.id || workspaceTree.lineage(of: $0.parentID).contains(fundFolder.id) })
print("  items: \(fund.items.map { "\($0.name)\($0.refusal.map { " (refused: \($0))" } ?? "")" })")
print("  prompts for the person: \(fund.prompts.map { "\($0.machine.map(String.init) ?? "-"): \($0.block)" })")
check("a refused item is named and the rest started", fund.refused.count == 1 && fund.machines.count == 4)
check("no consent was granted", try workspace.queries.policy() == CapturePolicy())
try workspace.rename(try child(workspace, "Team", of: nil).id, to: "Renamed")
check("the comparison sees a real change", try !Rows(workspace).keeps(before))

print("\n2. Fund added twice makes two teams")
let twice = try freshStore("twice")
let first = try twice.addTeam(.fund, having: [.taskRunner])
let second = try twice.addTeam(.fund, having: [.taskRunner])
let named = try twice.addTeam(.fund, name: "Brave deals", having: [.taskRunner])
let sameName = try twice.addTeam(.fund, name: "fund", having: [.taskRunner])
let teamNames = [first, second, named, sameName].map { $0.folder?.name ?? "none" }
print("  team folders: \(teamNames)")
check("four different folders", Set([first, second, named, sameName].compactMap { $0.folder?.id }).count == 4)
check(
    "code numbers a name that is taken, and keeps a free name",
    teamNames == ["Fund", "Fund 2", "Brave deals", "fund 3"])
let tasks = try twice.queries.machines().map(\.spec.task)
check("each team has its own four machines, with their own tasks", tasks.count == 16 && Set(tasks).count == 16)
let dealsFolders = try [first, second].map { try child(twice, "Deals", of: $0.folder?.id) }
check("each team has its own Deals folder", dealsFolders[0].id != dealsFolders[1].id)

print("\n3. A deal belongs to the rating machine of its own team")
let deals = try freshStore("deals")
try startAtRoot(deals, .startupTeam)
let teamA = try deals.addTeam(.fund, having: [.taskRunner])
let teamB = try deals.addTeam(.fund, having: [.taskRunner])
let oldestRater = try deals.queries.machines().with(\.rates)[0]
func dealOwner(_ team: TeamStart) throws -> (deal: WorkObject, owner: Machine?) {
    let folder = try child(deals, "Deals", of: team.folder?.id)
    let deal = try deals.createWorkObject(type: ObjectTypes.deal, parent: folder.id, name: "Acme")
    return (deal, try deals.queries.owner(of: deal, role: \.rates))
}
let dealA = try dealOwner(teamA)
let dealB = try dealOwner(teamB)
let tree = try deals.queries.folderTree()
func teamName(of folder: WorkObjectID?) -> String {
    tree.team(of: folder).flatMap { try? deals.queries.workObject($0)?.name } ?? "no team"
}
print(
    "  the oldest machine that rates in the workspace: \(oldestRater.name) in team \(teamName(of: oldestRater.folder))")
print("  deal in A's Deals: owner \(dealA.owner?.name ?? "none") of team \(teamName(of: dealA.owner?.folder))")
print("  deal in B's Deals: owner \(dealB.owner?.name ?? "none") of team \(teamName(of: dealB.owner?.folder))")
check("A's deal belongs to A's rating machine", tree.team(of: dealA.owner?.folder) == teamA.folder?.id)
check("B's deal belongs to B's rating machine, not the oldest", tree.team(of: dealB.owner?.folder) == teamB.folder?.id)
check("B's owner is not the workspace's oldest rating machine", dealB.owner?.id != oldestRater.id)
check(
    "the old rule, the oldest machine that rates, would have given B's deal to team A",
    tree.team(of: oldestRater.folder) == teamA.folder?.id)
let loose = try deals.createWorkObject(type: ObjectTypes.deal, parent: nil, name: "Loose")
let looseOwner = try deals.queries.owner(of: loose, role: \.rates)
print(
    "  a deal made with no team context and two folders that hold deals: parent \(loose.parentID ?? "none (the root)"); "
        + "owner \(looseOwner?.name ?? "none")")
check("it stays at the root, no folder is picked silently", loose.parentID == nil)
check("it borrows no machine of a team", looseOwner == nil)
let inA = try deals.queries.folderHolding(ObjectTypes.deal.id, within: teamA.folder?.id)
let inB = try deals.queries.folderHolding(ObjectTypes.deal.id, within: teamB.folder?.id)
let nowhere = try deals.queries.folderHolding(ObjectTypes.deal.id, within: nil)
check(
    "a deal made inside team B goes to team B's Deals folder",
    inB == (try child(deals, "Deals", of: teamB.folder?.id)).id)
check(
    "a deal made inside team A goes to team A's Deals folder",
    inA == (try child(deals, "Deals", of: teamA.folder?.id)).id)
check("with no context and two holders there is no answer", nowhere == nil)
check(
    "a linked item still decides first",
    {
        let linked = try? deals.queries.machines().owner(
            of: \.rates, linkedTasks: [dealA.owner!.task], folder: dealB.deal.parentID, in: tree)
        return linked?.id == dealA.owner?.id
    }())
let startupKeeper = try deals.queries.machines().with(\.keepsFacts).first
check(
    "a folder at the root of the workspace keeps the old answer",
    {
        let rootFolder = try? deals.queries.workObjects(parent: nil, includeArchived: false).first { $0.name == "Team" }
        return
            (try? deals.queries.machines().owner(
                of: \.keepsFacts, linkedTasks: [], folder: rootFolder?.id, in: tree))?.id == startupKeeper?.id
    }())

print("\n4. Machines for a new machine: the criteria to copy, and the keeper to follow")
let dealsB = try child(deals, "Deals", of: teamB.folder?.id)
let allKeepers = try deals.queries.machines().with(\.keepsFacts)
let allRaters = try deals.queries.machines().with(\.rates)
let rater = tree.nearest(in: allRaters, to: dealsB.id, folderOf: \.folder)
check("the criteria to copy come from team B's machine", tree.team(of: rater?.folder) == teamB.folder?.id)
let workspaceKeeper = tree.nearestOrFirstSharingTeam(in: allKeepers, with: nil, folderOf: \.folder)
check(
    "a machine added with no folder follows the keeper of the workspace itself, not a team's",
    workspaceKeeper != nil && tree.team(of: workspaceKeeper?.folder) == nil)

print("\n5. Today reads the facts of both teams, each with its own machine")
let today = try freshStore("today")
let one = try today.addTeam(.startupTeam)
let two = try today.addTeam(.startupTeam)
let todayTree = try today.queries.folderTree()
let keepers = try today.queries.machines().with(\.keepsFacts)
print(
    "  teams \([one, two].map { $0.folder?.name ?? "none" }); fact keepers \(keepers.map(\.name)) in teams "
        + "\(keepers.map { todayTree.team(of: $0.folder).flatMap { try? today.queries.workObject($0)?.name } ?? "none" })"
)
let moment = Date(timeIntervalSince1970: 1_790_000_000)
func fact(_ machine: Machine, _ person: String, _ kind: String) -> Item {
    Item(
        task: machine.task, day: WorkDay(containing: moment), scope: "", source: .typed, citeFirst: 1, citeLast: 1,
        start: moment, end: moment, fields: ["person": person, "kind": kind, "project": "Launch", "text": "x"],
        quote: "q", run: nil)
}
let facts = [fact(keepers[0], "Asha", "plan"), fact(keepers[1], "Ben", "blocker")]
let lifecycles = Dictionary(uniqueKeysWithValues: keepers.map { ($0.task, $0.spec.lifecycle) })
var input = MorningInput(facts: facts, me: "Meera")
input.ownerField = { lifecycles[$0.task]??.owner }
let sections = MorningList.pick(input, now: moment)
let waiting = sections.first { $0.kind == .waitingOn }?.owners.map(\.owner) ?? []
let groups = FactGroups.make(
    facts, by: { _ in "person" }, lifecycle: { lifecycles[$0.task] ?? nil }, now: moment)
print("  morning list, waiting on: \(waiting)")
print("  Today groups by person: \(groups.map(\.name))")
check("the morning list shows the owner of each team", waiting == ["Asha", "Ben"])
check("Today shows a group for each team's person, with none merged", groups.map(\.name).sorted() == ["Asha", "Ben"])
check("the two fact keepers have their own tasks", Set(keepers.map(\.task)).count == 2)
check("each keeper is in a different team", Set(keepers.compactMap { todayTree.team(of: $0.folder) }).count == 2)
let landing = try child(today, "Team", of: two.folder?.id)
let nearestKeeper = todayTree.nearestOrFirstSharingTeam(in: keepers, with: landing.id, folderOf: \.folder)
check(
    "a machine that lands in the second team follows the second team's keeper, not the oldest",
    nearestKeeper?.id == keepers[1].id && keepers[0].id != keepers[1].id)
let rostersMix = MemberRoster(names: ["Asha"]).member(for: "Ben") != nil
check("a roster of one team does not know the members of the other", !rostersMix)

print("\n6. Blank adds nothing")
let empty = try freshStore("blank")
try startAtRoot(empty, .startupTeam)
let beforeBlank = try Rows(empty)
let blank = try empty.addTeam(.blank)
check(
    "no folder and no machine was added", try Rows(empty) == beforeBlank && blank.folder == nil && blank.items.isEmpty)

print("\n7. A Need refusal leaves the rest of the team started")
let refused = try freshStore("refused").addTeam(.fund)
let started = refused.items.filter { $0.refusal == nil }.map(\.name)
print("  started \(started); refused \(refused.refused)")
check("the research item is refused and named", refused.refused == ["Research a company needs a model with tools."])
check("the other five items started", started.count == 5)
let allRefused = try freshStore("refused-all")
let none = try allRefused.addTeam(
    TeamTemplate(
        id: "needy", name: "Needy", purpose: "", objectTypes: [],
        machines: [TeamMachine(template: GalleryTemplate.companyResearch.id, name: "Research")]))
let refusedAllBefore = try Rows(allRefused)
check("a team whose every item is refused starts no machine", none.machines.isEmpty && none.refused.count == 1)
let afterRefusal = try Rows(allRefused)
check("and leaves no team folder", none.folder == nil && afterRefusal == refusedAllBefore)

func startKey(_ store: Store, _ id: WorkObjectID) throws -> String? {
    try store.writer.read { db in
        try String.fetchOne(db, sql: "SELECT start_key FROM work_object WHERE id = ?", arguments: [id])
    }
}

let dealItem = try! need(GalleryTemplate.of(id: MachineTemplate.dealIntake.id))

print("\n8. A store from before the key step migrates by structure and loses nothing")
let oldFolder = scratch.appending(path: "old-shape")
try FileManager.default.createDirectory(at: oldFolder, withIntermediateDirectories: true)
let oldQueue = try DatabaseQueue(path: oldFolder.appending(path: "workbench.sqlite").path)
let beforeStep = Schema.steps.firstIndex(of: Schema.startKey)!
let folderType = ObjectTypes.folder.id
let pageType = ObjectTypes.machinePage.id
try oldQueue.write { db in
    for statement in Schema.steps.prefix(beforeStep).joined() { try db.execute(sql: statement) }
    try db.execute(sql: "PRAGMA user_version = \(beforeStep)")
    func node(_ id: String, _ type: String, _ parent: String?, _ name: String) throws {
        try db.execute(
            sql: "INSERT INTO work_object(id, type, parent_id, position, name) VALUES (?,?,?, ?, ?)",
            arguments: [id, type, parent, Double(id.hashValue & 0xFF), name])
    }
    func machine(_ task: String, _ template: String, page: String, in folder: String) throws {
        try node(page, pageType, folder, task)
        try db.execute(
            sql: "INSERT INTO machine(task, template, created_at, page_id) VALUES (?,?, '2026-11-01T00:00:00Z', ?)",
            arguments: [task, template, page])
    }
    try node("renamed-deals", folderType, nil, "Pipeline")
    try node("second-deals", folderType, nil, "Deals")
    try node("people", folderType, nil, "My crew")
    try node("watch", folderType, nil, "Watchlist")
    try node("research-1", folderType, nil, "Research")
    try node("research-2", folderType, nil, "Research")
    try node("notes", folderType, nil, "Notes")
    try node("notes-sub", folderType, "notes", "Sub")
    try machine("deal-1", MachineTemplate.dealIntake.id, page: "page-1", in: "renamed-deals")
    try machine("deal-2", MachineTemplate.dealIntake.id, page: "page-2", in: "second-deals")
    try machine("pip-1", MachineTemplate.team.id, page: "page-3", in: "people")
}
func oldRows(_ queue: DatabaseQueue) throws -> [Row] {
    try queue.read { db in
        try Row.fetchAll(
            db,
            sql: "SELECT id, type, parent_id, position, name, archived_at, holds FROM work_object ORDER BY id")
            + Row.fetchAll(db, sql: "SELECT * FROM machine ORDER BY id")
    }
}
let rowsBefore = try oldRows(oldQueue)
let migrated = try Store(directory: oldFolder)
let rowsAfter = try oldRows(oldQueue)
let keys = try oldQueue.read { db in
    Dictionary(
        uniqueKeysWithValues: try Row.fetchAll(db, sql: "SELECT id, start_key FROM work_object").map {
            ($0["id"] as String, $0["start_key"] as String?)
        })
}
print("  keys: \(keys.filter { $0.value != nil }.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value!)" })")
check("every row is equal before and after, apart from the new column", rowsBefore == rowsAfter)
check("a renamed folder that holds a machine page takes the key of its template", keys["renamed-deals"] == "deals")
check("a folder of another machine template takes that key", keys["people"] == "team")
check("a second folder for a key that a sibling has stays without a key", keys["second-deals"] == .some(nil))
check("a root folder with no machine and the exact name takes the key", keys["watch"] == "watchlist")
check(
    "two root folders with the same exact name take none",
    keys["research-1"] == .some(nil) && keys["research-2"] == .some(nil))
check(
    "a folder of the person, and its sub-folder, get none",
    keys["notes"] == .some(nil) && keys["notes-sub"] == .some(nil))
check("no existing folder is a team", keys.values.allSatisfy { !($0 ?? "").hasPrefix("team:") })
let quick = try oldQueue.read { try String.fetchAll($0, sql: "PRAGMA quick_check") }
check("quick_check says ok", quick == ["ok"])
let version = try oldQueue.read { try Int.fetchOne($0, sql: "PRAGMA user_version") }
check("the store is at the last step", version == Schema.steps.count)
check("the migrated store reads and has no team", try migrated.queries.folderTree().team(of: "renamed-deals") == nil)
let startedAgain = try migrated.start(dealItem)
check("starting Deals at the root finds the renamed folder, not a new one", startedAgain.folder.id == "renamed-deals")

print("\n9. Rename then start finds the same folder; archive then start makes a new one")
let keyed = try freshStore("keyed")
let keyedTeam = try keyed.addTeam(.fund, having: [.taskRunner])
let teamID = keyedTeam.folder!.id
let original = try child(keyed, "Deals", of: teamID)
let folderCount = try children(keyed, of: teamID).count
try keyed.rename(original.id, to: "Pipeline")
let found = try keyed.start(dealItem, parent: teamID)
check("a renamed folder is found again", found.folder.id == original.id)
check("no folder was added", try children(keyed, of: teamID).count == folderCount)
try keyed.archive(original.id)
check("archive clears the key", try startKey(keyed, original.id) == nil)
let fresh = try keyed.start(dealItem, parent: teamID)
check(
    "after an archive a start makes a new keyed folder", fresh.folder.id != original.id && fresh.folder.name == "Deals")
check("and it carries the key", try startKey(keyed, fresh.folder.id) == "deals")

print("\n10. Move with and without a key clash")
let moving = try freshStore("moving")
let keyedRoot = try moving.start(dealItem).folder
let box = try moving.createWorkObject(type: ObjectTypes.folder, parent: nil, name: "Box")
let busy = try moving.createWorkObject(type: ObjectTypes.folder, parent: nil, name: "Busy")
let busyDeals = try moving.start(dealItem, parent: busy.id).folder
try moving.move(keyedRoot.id, under: box.id)
check("a keyed folder moved where the key is free keeps it", try startKey(moving, keyedRoot.id) == "deals")
try moving.move(keyedRoot.id, under: busy.id)
check("moved where the parent has the key, it loses its key", try startKey(moving, keyedRoot.id) == nil)
check("the folder already there keeps its key", try startKey(moving, busyDeals.id) == "deals")

print("\n11. The unique index: one live key per parent")
let index = try freshStore("index")
let oneFolder = try index.createWorkObject(type: ObjectTypes.folder, parent: nil, name: "One")
let twoFolder = try index.createWorkObject(type: ObjectTypes.folder, parent: nil, name: "Two")
func insertKeyed(_ parent: WorkObjectID?, _ id: String) throws {
    try index.writer.write { db in
        try db.execute(
            sql: "INSERT INTO work_object(id, type, parent_id, position, name, start_key) VALUES (?,?,?,1,'x','k')",
            arguments: [id, folderType, parent])
    }
}
try insertKeyed(oneFolder.id, "a")
check("the same key under another parent is allowed", (try? insertKeyed(twoFolder.id, "b")) != nil)
check("a second live folder with the key under one parent is refused", (try? insertKeyed(oneFolder.id, "c")) == nil)
check(
    "two roots with the same key are refused too",
    {
        (try? insertKeyed(nil, "d")) != nil && (try? insertKeyed(nil, "e")) == nil
    }())

print("\n12. Only the team key makes a team")
let owned = try freshStore("owned")
let plain = try owned.createWorkObject(type: ObjectTypes.folder, parent: nil, name: "Plain")
let inner = try owned.createWorkObject(type: ObjectTypes.folder, parent: plain.id, name: "Inner")
let innerer = try owned.createWorkObject(type: ObjectTypes.folder, parent: inner.id, name: "Innermost")
var ownedTree = try owned.queries.folderTree()
check("a plain root folder with sub-folders is not a team", ownedTree.team(of: innerer.id) == nil)
let ownTeam = try owned.addTeam(.fund, having: [.taskRunner])
let ownDeals = try child(owned, "Deals", of: ownTeam.folder?.id)
ownedTree = try owned.queries.folderTree()
check("a folder of a team sits in that team", ownedTree.team(of: ownDeals.id) == ownTeam.folder?.id)
try owned.move(ownTeam.folder!.id, under: plain.id)
ownedTree = try owned.queries.folderTree()
check(
    "a moved team folder is still a team, and the folder it moved under is not",
    {
        ownedTree.team(of: ownDeals.id) == ownTeam.folder?.id && ownedTree.team(of: inner.id) == nil
    }())
check(
    "the team key cannot equal the key of a gallery folder",
    try {
        let key = try need(startKey(owned, ownTeam.folder!.id))
        return key.hasPrefix("team:fund:") && !GalleryTemplate.all.map(\.folder.key).contains(key)
    }())
try owned.archive(ownTeam.folder!.id)
ownedTree = try owned.queries.folderTree()
check("an archived team is not a team", ownedTree.team(of: ownDeals.id) == nil)

print("\n13. A machine that follows facts is started with a keeper to follow")
func store(_ item: Item, in store: Store) throws {
    try store.writer.write { db in _ = try Store.insertItem(db, item, at: moment) }
}
func machine(_ role: KeyPath<HelperSpec, Bool>, in team: TeamStart, of store: Store) throws -> Machine {
    let tree = try store.queries.folderTree()
    return try need(store.queries.machines().with(role).first { tree.team(of: $0.folder) == team.folder?.id })
}
let followed = try freshStore("followed")
let onlyTeam = try followed.addTeam(.startupTeam)
let pipOfTeam = try machine(\.keepsFacts, in: onlyTeam, of: followed)
let watchOfTeam = try machine(\.needsFollowed, in: onlyTeam, of: followed)
try store(fact(pipOfTeam, "Asha", "plan"), in: followed)
let seen = try followed.queries.openItems(readBy: watchOfTeam.spec)
print("  \(watchOfTeam.name) follows \(watchOfTeam.spec.follows ?? "nothing"); Pip is \(pipOfTeam.spec.task)")
check("the follower follows the keeper of its team", watchOfTeam.spec.follows == pipOfTeam.spec.task)
check("it reads the open facts of that keeper", seen.items.count == 1 && seen.items[0].task == pipOfTeam.spec.task)

let twoTeams = try freshStore("two-followers")
let teamOne = try twoTeams.addTeam(.startupTeam)
let teamTwo = try twoTeams.addTeam(.startupTeam)
let pipOne = try machine(\.keepsFacts, in: teamOne, of: twoTeams)
let pipTwo = try machine(\.keepsFacts, in: teamTwo, of: twoTeams)
let watchOne = try machine(\.needsFollowed, in: teamOne, of: twoTeams)
let watchTwo = try machine(\.needsFollowed, in: teamTwo, of: twoTeams)
try store(fact(pipOne, "Asha", "plan"), in: twoTeams)
try store(fact(pipTwo, "Ben", "plan"), in: twoTeams)
check(
    "each follower follows its own team's keeper",
    watchOne.spec.follows == pipOne.spec.task && watchTwo.spec.follows == pipTwo.spec.task)
let readOne = try twoTeams.queries.openItems(readBy: watchOne.spec).items.map(\.task)
let readTwo = try twoTeams.queries.openItems(readBy: watchTwo.spec).items.map(\.task)
check("each reads only the facts of its own team", readOne == [pipOne.spec.task] && readTwo == [pipTwo.spec.task])

let followerFirst = TeamTemplate(
    id: "follower-first", name: "Follower first", purpose: "", objectTypes: [],
    machines: [
        TeamMachine(template: MachineTemplate.derailment.id, name: "Watch"),
        TeamMachine(template: MachineTemplate.team.id, name: "Keeper"),
    ])
let ordered = try freshStore("ordered")
let orderedTeam = try ordered.addTeam(followerFirst)
let orderedKeeper = try machine(\.keepsFacts, in: orderedTeam, of: ordered)
let orderedWatch = try machine(\.needsFollowed, in: orderedTeam, of: ordered)
check(
    "the order of the items does not matter: the keeper starts first",
    orderedWatch.spec.follows == orderedKeeper.spec.task && orderedTeam.items.map(\.name) == ["Watch", "Keeper"])

let alone = try freshStore("alone")
let aloneBefore = try Rows(alone)
let followerOnly = TeamTemplate(
    id: "follower-only", name: "Follower only", purpose: "", objectTypes: [],
    machines: [TeamMachine(template: MachineTemplate.derailment.id, name: "Watch")])
let aloneStart = try alone.addTeam(followerOnly)
let aloneAfter = try Rows(alone)
print("  a template with only a follower: \(aloneStart.refused)")
check(
    "a template with only a follower is refused with the reason, and nothing starts",
    aloneStart.refused.count == 1 && aloneStart.refused[0].contains(GalleryStartError.nothingToFollowWords)
        && aloneStart.folder == nil && aloneAfter == aloneBefore)
let derailment = try need(GalleryTemplate.of(id: MachineTemplate.derailment.id))
let refusedAlone = (try? alone.start(derailment)) == nil
let aloneAfterStart = try Rows(alone)
check(
    "Store.start refuses a follower with no keeper and makes no folder", refusedAlone && aloneAfterStart == aloneBefore)
let beside = try freshStore("beside")
try beside.addTeam(.startupTeam)
let besideBefore = try Rows(beside)
let besideStart = try beside.addTeam(followerOnly)
let besideAfter = try Rows(beside)
check(
    "a follower is refused when the only keeper is in another team",
    besideStart.refused.count == 1 && besideStart.folder == nil && besideAfter == besideBefore)

let existing = try freshStore("existing-follower")
let oldWatch = try existing.createMachine(from: .derailment, template: MachineTemplate.derailment.id, name: "Old watch")
let existingBefore = try Rows(existing)
try existing.addTeam(.startupTeam)
let existingAfter = try Rows(existing)
let oldWatchAfter = try need(existingAfter.machines.first { $0.id == oldWatch.id })
check(
    "a follower made before is unchanged, and still has no follows",
    existingAfter.keeps(existingBefore) && oldWatchAfter.spec.follows == nil)

print(failures == 0 ? "\nALL OK" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
