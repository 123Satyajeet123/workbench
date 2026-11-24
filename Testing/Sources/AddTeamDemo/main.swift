import Foundation
import WorkbenchCore

/// Shows that a team template starts inside an existing workspace, beside the teams already there, in both directions:
/// the rows before stay as they were, a second add makes a second team, each deal is read by the machines of its own
/// team, Today reads both teams, Blank adds nothing, and a refused item leaves the rest of the team started. It uses
/// scratch stores and no network.

var failures = 0

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
        task: machine.task, day: WorkDay(containing: moment), scope: "", source: .whatsapp, citeFirst: 1, citeLast: 1,
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
check("a team whose every item is refused starts no machine", none.machines.isEmpty && none.refused.count == 1)

print(failures == 0 ? "\nALL OK" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
