import Foundation
import WorkbenchCore

/// Shows that every first run goes through `Store.start`, in both directions: what each team template makes, the
/// refusal of an item that needs more than the app has, the picker as a prompt with no grant, the ratings of the old
/// fixed levels against levels as data, and the order of the levels. It uses scratch stores and no network.

func yes(_ ok: Bool) -> String { ok ? "yes" : "NO" }

let scratch = FileManager.default.temporaryDirectory.appending(path: "templates-start-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: scratch) }

func freshStore(_ name: String) throws -> Store { try Store(directory: scratch.appending(path: name)) }

func folderName(_ store: Store, _ id: WorkObjectID?) throws -> String {
    try id.flatMap { try store.queries.workObject($0)?.name } ?? "none"
}

print("1. Each team template starts through Store.start")
for team in TeamTemplate.builtIn {
    let store = try freshStore(team.id)
    let started = try store.addTeam(team)
    let folders = try store.queries.workObjects(parent: nil, includeArchived: false).map(\.name)
    print("  \(team.name): folders \(folders); refused \(started.refused)")
    for machine in try store.queries.machines() {
        let home = try folderName(store, machine.folder)
        print("    \(machine.name) in \(home), shows its facts as \(machine.spec.view)")
    }
    let deal = try store.createWorkObject(type: ObjectTypes.deal, parent: nil, name: "Probe deal")
    print("    a new deal lands in: \(try folderName(store, deal.parentID))")
}

print("\n2. holds: the folder of the Fund takes a new deal; a folder with no holds does not")
let fund = try freshStore("holds-fund")
try fund.addTeam(.fund)
let deal = try fund.createWorkObject(type: ObjectTypes.deal, parent: nil, name: "Probe deal")
let plain = try freshStore("holds-startup")
try plain.addTeam(.startupTeam)
let loose = try plain.createWorkObject(type: ObjectTypes.deal, parent: nil, name: "Probe deal")
let dealFolder = try folderName(fund, deal.parentID)
print("  Fund: deal goes in \(dealFolder): \(yes(dealFolder == "Deals"))")
print("  Startup team: deal stays a root, no folder holds deals: \(yes(loose.parentID == nil))")

print("\n3. Need: one check in Store.start")
let needy = try freshStore("need")
do {
    try needy.start(.companyResearch)
    print("  refused: NO")
} catch {
    print("  refused: \(error.localizedDescription)")
}
let madeByRefusal = try needy.queries.workObjects(parent: nil, includeArchived: false)
print("  no folder was made by the refusal: \(yes(madeByRefusal.isEmpty))")
let given = try needy.start(.companyResearch, having: [.taskRunner])
print("  with what it needs, it starts: folder \(given.folder.name), machine \(given.machine?.name ?? "none")")
let fundStart = try freshStore("need-fund").addTeam(.fund, having: [.taskRunner])
print("  Fund with a tool model refuses nothing: \(yes(fundStart.refused.isEmpty))")

print("\n4. The picker is a prompt, never a grant")
let granting = try freshStore("grant")
let before = try granting.queries.policy()
let pip = try granting.start(.whatsAppReminders)
let after = try granting.queries.policy()
print("  prompts: \(pip.prompts)")
print("  consent unchanged by the start: \(yes(before == after))")
try granting.savePolicy(CapturePolicy(switches: [.whatsapp: true]))
print("  the check sees a real change: \(yes(try granting.queries.policy() != after))")
let board = pip.machine.map { $0.spec.views["board"] == $0.spec.view }
print("  the facts block set the default view to the board: \(yes(board == true))")

print("\n5. Rating levels as data give the old ratings")
/// The rating of the old closed enum, written out: hot from `hotAt` points, warm from 0, else cold.
func oldRating(_ verdicts: [Verdict], hotAt: Int) -> String {
    let (breaker, must, plusA, plusB, minusA, minusB) = (
        verdicts[0], verdicts[1], verdicts[2], verdicts[3], verdicts[4], verdicts[5]
    )
    if breaker == .fail || must == .fail { return "cold" }
    let points = [plusA, plusB].filter { $0 == .pass }.count - [minusA, minusB].filter { $0 == .fail }.count
    let rating = points >= hotAt ? "hot" : points >= 0 ? "warm" : "cold"
    let holds = [breaker, must].contains(.unknown)
    return holds && rating == "hot" ? "warm" : rating
}
let roles: [Rule.Role] = [.dealBreaker, .must, .plus, .plus, .minus, .minus]
let answers: [Verdict: String] = [.pass: "yes", .fail: "no", .unknown: "unclear"]
let all: [Verdict] = [.pass, .fail, .unknown]
var compared = 0
var different = 0
for hotAt in 0...3 {
    let rules = roles.enumerated().map {
        Rule(id: "r\($0.offset)", role: $0.element, test: .text(TextTest(says: "x", wants: true)))
    }
    let criteria = Criteria(rules: rules, levels: Level.standard(topCut: hotAt))
    var verdicts = [Verdict](repeating: .pass, count: 6)
    for code in 0..<729 {
        var rest = code
        for index in 0..<6 {
            verdicts[index] = all[rest % 3]
            rest /= 3
        }
        let fields = Dictionary(
            uniqueKeysWithValues: verdicts.enumerated().map { ("r\($0.offset)", answers[$0.element]!) })
        compared += 1
        if criteria.triage(fields).rating != oldRating(verdicts, hotAt: hotAt) { different += 1 }
    }
}
print("  \(compared) rule-result sets over four cuts, differing from the old enum: \(different)")
let legacy = try JSONDecoder().decode(Criteria.self, from: Data(#"{"rules":[],"hotAt":3}"#.utf8))
print(
    "  a stored criteria with hotAt 3 reads as levels \(legacy.levels.map { "\($0.name)@\($0.cut.map(String.init) ?? "-")" })"
)
print("  the table is made from the levels: \(Criteria().table[3])")

print("\n6. The level order sorts")
let tiers = Criteria(
    rules: [
        Rule(id: "ra", role: .plus, test: .text(TextTest(says: "a", wants: true))),
        Rule(id: "rb", role: .plus, test: .text(TextTest(says: "b", wants: true))),
    ], levels: [Level("gold", cut: 2), Level("silver", cut: 1), Level("bronze")])
func item(_ name: String, _ ra: String, _ rb: String) -> Item {
    let when = Date(timeIntervalSince1970: 1_790_000_000)
    return Item(
        task: "demo", day: WorkDay(containing: when), scope: "", source: .web, citeFirst: 1, citeLast: 1, start: when,
        end: when, fields: ["name": name, "company": name, "ra": ra, "rb": rb], quote: "q", run: nil)
}
let items = [item("none", "no", "no"), item("both", "yes", "yes"), item("one", "yes", "no")]
var spec = HelperSpec.dealIntake
spec.criteria = tiers
let order = FirstLook.shown(items, by: spec, at: .now).map { $0.fields["name"] ?? "" }
let names = items.map { tiers.triage($0.fields).rating }
print("  levels \(tiers.levels.map(\.name)); items none, both, one rate \(names)")
print("  first look order, best level first: \(order): \(yes(order == ["both", "one", "none"]))")
let ranked = OutboundReview.rank(items, criteria: tiers).map(\.company)
print("  outbound order uses the same levels: \(ranked == ["both", "one", "none"] ? "yes" : "NO") \(ranked)")
