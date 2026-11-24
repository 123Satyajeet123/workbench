import WorkbenchCore

/// Prints the gallery as data and checks that each template holds together, and that the check finds a broken one.
func report(_ template: GalleryTemplate) {
    let machine = template.machine.map { "\($0.name) (\($0.spec.task), reads \($0.spec.source.consent.rawValue))" }
    print("\(template.name)  [\(template.icon)]")
    print("  folder: \(template.folder.name)\(template.folder.holds.map { ", holds \($0)" } ?? "")")
    print("  machine: \(machine ?? "none")  needs: \(template.needs.map(\.rawValue).sorted())")
    print("  job: \(template.job)")
    print("  blocks: \(template.blocks)")
    print("  problems: \(template.problems.isEmpty ? "none" : template.problems.joined(separator: "; "))")
}

GalleryTemplate.all.forEach(report)
let clean = GalleryTemplate.all.allSatisfy(\.problems.isEmpty)
print("\nAll \(GalleryTemplate.all.count) hold together: \(clean ? "yes" : "NO")")
print("Featured, in the founder's order: \(GalleryTemplate.featured.map(\.name))")

for team in TeamTemplate.builtIn {
    print("\n\(team.name): items \(team.items.map(\.name)); machines \(team.seeds.map(\.name))")
    for seed in team.seeds {
        print("  \(seed.name) goes in folder \(GalleryTemplate.folder(forMachine: seed.spec.task).name)")
    }
}
let plain = GalleryTemplate.of(id: MachineTemplate.timeline.id)
print(
    "A machine with no gallery entry gets a plain one in General: "
        + "\(plain?.folder.name == GalleryTemplate.generalFolder && plain?.problems == [] ? "yes" : "NO")")
print("An unknown id gives nothing: \(GalleryTemplate.of(id: "no.such.machine") == nil ? "yes" : "NO")")

let broken = GalleryTemplate(
    id: "broken", name: "Broken", icon: "xmark", detail: "", folder: .init(name: "Broken"), machine: .followUps,
    job: "", blocks: [.picker(.mail), .input(.criteria), .facts(task: HelperSpec.followUps.task, view: "board")])
print("A broken template is caught: \(broken.problems.count == 3 ? "yes" : "NO") \(broken.problems)")
print("Ids are unique: \(Set(GalleryTemplate.all.map(\.id)).count == GalleryTemplate.all.count ? "yes" : "NO")")
