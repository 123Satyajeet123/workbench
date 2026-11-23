import WorkbenchCore

/// Prints the gallery as data and checks that each template holds together, and that the check finds a broken one.
func report(_ template: GalleryTemplate) {
    let machine = template.machine.map { "\($0.name) (\($0.spec.task), reads \($0.spec.source.kind.rawValue))" }
    print("\(template.name)  [\(template.icon)]")
    print("  folder: \(template.folder.name)\(template.folder.holds.map { ", holds \($0)" } ?? "")")
    print("  machine: \(machine ?? "none")  needs: \(template.needs.map(\.rawValue).sorted())")
    print("  job: \(template.job)")
    print("  blocks: \(template.blocks)")
    print("  problems: \(template.problems.isEmpty ? "none" : template.problems.joined(separator: "; "))")
}

GalleryTemplate.all.forEach(report)
let clean = GalleryTemplate.all.allSatisfy(\.problems.isEmpty)
print("\nAll six hold together: \(clean ? "yes" : "NO")")

let broken = GalleryTemplate(
    id: "broken", name: "Broken", icon: "xmark", detail: "", folder: .init(name: "Broken"), machine: .followUps,
    job: "", blocks: [.picker(.mail), .input(.criteria), .facts(task: HelperSpec.followUps.task, view: "board")])
print("A broken template is caught: \(broken.problems.count == 3 ? "yes" : "NO") \(broken.problems)")
print("Ids are unique: \(Set(GalleryTemplate.all.map(\.id)).count == GalleryTemplate.all.count ? "yes" : "NO")")
