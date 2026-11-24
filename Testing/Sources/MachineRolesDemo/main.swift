import Foundation
import WorkbenchCore

/// Shows that code finds machines by role: the roles of every built-in machine, the same answers as the old name
/// rules, a second Pip and a renamed template, and the count of identity branches left in Sources.

func yes(_ ok: Bool) -> String { ok ? "yes" : "NO" }

func rolesText(_ spec: HelperSpec) -> String {
    let roles = [
        ("keepsFacts", spec.keepsFacts), ("rates", spec.rates), ("checksClaims", spec.checksClaims),
        ("readsScreen", spec.readsScreen), ("readsFacts", spec.needsFollowed),
    ]
    return roles.filter(\.1).map(\.0).joined(separator: ", ")
}

let scratch = FileManager.default.temporaryDirectory.appending(path: "machine-roles-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: scratch) }

print("1. Roles of every built-in machine (spec only)")
for template in MachineTemplate.all {
    print("  \(template.name.padding(toLength: 16, withPad: " ", startingAt: 0)) \(rolesText(template.spec))")
}
for (name, spec) in HelperSpec.withoutMachine {
    print("  \(name.padding(toLength: 16, withPad: " ", startingAt: 0)) \(rolesText(spec))   (no machine)")
}

print("\n2. Roles give the answers the name rules gave, for the built-in machines")
let all = MachineTemplate.all
let timelineSet = all.filter(\.spec.readsScreen).map(\.id)
print("  screen readers = [\(MachineTemplate.timeline.id)]: \(yes(timelineSet == [MachineTemplate.timeline.id]))")
let watchers = all.filter(\.spec.needsFollowed).map(\.id)
print("  fact readers = [\(MachineTemplate.derailment.id)]: \(yes(watchers == [MachineTemplate.derailment.id]))")
let keepers = all.filter(\.spec.keepsFacts).map(\.name)
print("  fact keepers: \(keepers)")

let builtInStore = try Store(directory: scratch.appending(path: "built-in"))
for template in all { try builtInStore.createMachine(from: template.spec, template: template.id, name: template.name) }
let builtIns = try builtInStore.queries.machines()
let oldThesis = builtIns.lazy.compactMap(\.spec.criteria).first
let newThesis = builtIns.owner(of: \.rates, linkedTasks: [], folder: nil)?.spec.criteria
print("  no link, no folder: same thesis as the old first machine with criteria: \(yes(oldThesis == newThesis))")
let oldTypes = builtIns.lazy.compactMap(\.spec.claimTypes).first
let newTypes = builtIns.owner(of: \.checksClaims, linkedTasks: [], folder: nil)?.spec.claimTypes
print("  same claim types as the old first machine with claim types: \(yes(oldTypes == newTypes))")

print("\n3. A second Pip, a renamed template, and the owner of a deal")
let store = try Store(directory: scratch.appending(path: "second"))
let funds = try store.createWorkObject(type: ObjectTypes.folder, parent: nil, name: "Fund A")
let studio = try store.createWorkObject(type: ObjectTypes.folder, parent: nil, name: "Fund B")
_ = try store.createMachine(from: .team, template: MachineTemplate.team.id, name: "Pip", in: funds.id)
_ = try store.createMachine(from: .team, template: MachineTemplate.team.id, name: "Second Pip", in: studio.id)
let renamed = try store.createMachine(from: .team, template: "renamed.team.v2", name: "Hand notes", in: studio.id)
try store.rename(renamed, to: "Notes by Asha")
let intakeA = try store.createMachine(from: .dealIntake, template: "deal.intake", name: "Intake A", in: funds.id)
let intakeB = try store.createMachine(from: .dealIntake, template: "renamed.intake", name: "Intake B", in: studio.id)
try store.setCriteria(intakeB, Criteria())
let crew = try store.queries.machines()
print("  fact keepers: \(crew.with(\.keepsFacts).map(\.name))")
print("  fact keepers in Fund B: \(crew.with(\.keepsFacts).filter { $0.folder == studio.id }.map(\.name))")
let byLink = crew.owner(of: \.rates, linkedTasks: [intakeB.task], folder: funds.id)
let byFolder = crew.owner(of: \.rates, linkedTasks: [], folder: studio.id)
let byOldest = crew.owner(of: \.rates, linkedTasks: [], folder: nil)
print("  deal linked to Intake B's item, in Fund A: owner \(byLink?.name ?? "none") (the item's own machine)")
print("  deal with no link, in Fund B: owner \(byFolder?.name ?? "none") (the folder's machine)")
print("  deal with no link and no folder: owner \(byOldest?.name ?? "none") (the oldest machine that rates)")
let found = byLink?.id == intakeB.id && byFolder?.folder == studio.id && byOldest?.id == intakeA.id
print("  each owner is the one the data names: \(yes(found))")

print("\n4. Identity branches left in Sources, by the pattern of the inventory")

/// A line the pattern finds that is generic: it looks a machine up by an id the data carries.
struct Generic {
    let file: String
    let code: String
    let reason: String

    init(_ file: String, _ code: String, _ reason: String) {
        (self.file, self.code, self.reason) = (file, code, reason)
    }
}

let byDataId = "looks up by the task of an item, run or argument that the data carries"
let genericLines = [
    Generic(
        "CallActions.swift", "HelperSpec.callFollowUps.task", "the call pipeline reads its own output by its own spec"),
    Generic("Timers.swift", "$0.task == fact.task", "matches a policy to the task of the fact"),
    Generic("Summaries.swift", "$0.task == task", byDataId),
    Generic("ShareDayRow.swift", "refusal.task == model.spec.task", "compares the machine's own task with a refusal"),
    Generic("Catalog.swift", "$0.task == task", byDataId),
    Generic("Catalog.swift", "$0.task == spec.task", "compares the machine's own task with a review"),
    Generic("MachineRoles.swift", "$0.task == task", "finds the machine of an item the deal links"),
    Generic("ItemStore.swift", "$0.task == follows", "reads the task a spec follows from the spec"),
    Generic("TodayModel.swift", "$0.task == machine.task", "keeps the facts of the machine at hand"),
    Generic("TodayModel.swift", "crew.helper(task: item.task)", byDataId),
    Generic("ProofModel.swift", "$0.spec.task == item.task", byDataId),
    Generic("TeamCatalogModel.swift", "helper.spec.task", "compares the machine's own task with shared ones"),
    Generic("TeamCatalogModel+Audience.swift", "machine.spec.task", "compares the machine's own task with reviews"),
    Generic("CrewCardFacts.swift", "$0.task == task", "filters runs and quality by the card's own task"),
    Generic("DealDigest.swift", "$0.task == linked.task", "finds the machine of a linked item by the task it carries"),
    Generic("AutomationStrip.swift", "$0.task == machine.task", "filters runs by the row's own machine"),
    Generic("ReviewModel.swift", "helper(task:", byDataId),
    Generic("FactActing.swift", "$0.spec.task == task", byDataId),
    Generic("Crew.swift", "$0.spec.task == task", "finds a spec by a task, in the one list of facts no machine keeps"),
    Generic("Crew.swift", "func helper(task:", byDataId),
    Generic("Crew.swift", "helper(task: task)", byDataId),
    Generic("HelperModel.swift", "$0.task == spec.task", "reads the quality of the machine's own task"),
    Generic("TeamStep.swift", "template == model.teamModel.template", "marks the chosen card of a list"),
    Generic("MachineSheet.swift", "template == nil", "checks that the person picked a template"),
    Generic("MemberRoster.swift", "item.task == task", "checks that a fact is the machine's own"),
    Generic("FirstLookModel.swift", "helper(task:", byDataId),
]

let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
let sources = ["Packages/WorkbenchCore/Sources", "Packages/WorkbenchUI/Sources", "Workbench"]

/// Prints each line of Sources that `pattern` finds, as class B when `generic` explains it and as class A when not.
/// Returns the count of class A.
func scan(_ pattern: String, generic: [Generic]) throws -> Int {
    let expression = try NSRegularExpression(pattern: pattern)
    var hits: [(file: String, line: Int, text: String)] = []
    for source in sources {
        let folder = root.appending(path: source)
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        for case let url as URL in files ?? .init()
        where url.pathExtension == "swift" && !url.path.contains("/Templates/")
            && !url.path.hasSuffix("Helpers/BuiltIn.swift")
        {
            let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
            for (index, text) in lines.enumerated()
            where expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                hits.append((url.lastPathComponent, index + 1, text.trimmingCharacters(in: .whitespaces)))
            }
        }
    }
    var unexplained = 0
    for hit in hits {
        if let known = generic.first(where: { $0.file == hit.file && hit.text.contains($0.code) }) {
            print("  B  \(hit.file):\(hit.line)  \(known.reason)")
        } else {
            unexplained += 1
            print("  A  \(hit.file):\(hit.line)  \(hit.text)")
        }
    }
    print("  lines: \(hits.count); class A: \(unexplained); class B: \(hits.count - unexplained)")
    return unexplained
}

let inventory = #"template *==|\.task *==|helper\(task:|MachineTemplate\.[a-zA-Z]+\.id|HelperSpec\.[a-zA-Z]+\.task"#
let inventoryA = try scan(inventory, generic: genericLines)
print("  the inventory had 41 lines at 7c7d3141; class A is 0: \(yes(inventoryA == 0))")

print("\n5. Other identity branches: a named machine, or the first machine of a template or role")
let named =
    #"crew\.(team|timeline|sentinel)\b|factMachines|intakeCriteria|\.followable\b|queries\.(thesis|claimTypes)\(\)|HelperSpec\.(team|teamTelegram|timeline|pages|dealIntake|outbound|derailment|followUps|callFollowUps|founderCheck|newsSignals)\b|MachineTemplate\.(team|timeline|derailment|dealIntake|outbound)\b"#
let outside = "the call pipeline's own spec (Echo is M5), or onboarding and the add sheet (M8)"
let namedLines = [
    Generic("CallEvidence.swift", "HelperSpec.callFollowUps", outside),
    Generic("CallActions.swift", "HelperSpec.callFollowUps", outside),
    Generic("SignalLine.swift", "HelperSpec.newsSignals", "the tones of the news spec, a feature of its own (M5)"),
    Generic("MachineSheet.swift", "MachineTemplate.team", "the add sheet's first choice (M8)"),
    Generic("WelcomeStep.swift", "MachineTemplate.team", "the welcome screen's card (M8)"),
]
let namedA = try scan(named, generic: namedLines)
print("  named machines left unexplained: \(namedA)")
