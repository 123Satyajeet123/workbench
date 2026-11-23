import Foundation
import WorkbenchCore

// Counts what the filing step does to a store, on a copy of it. Usage: work-objects-dry-run <store folder>.
// The folder is a backup copy of the store. The tool prints counts and task names only.
guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: work-objects-dry-run <store folder>\n".utf8))
    exit(2)
}
let report = try WorkObjectsDryRun.run(onCopyOf: URL(filePath: CommandLine.arguments[1]))
func lines(_ title: String, _ counts: [String: Int]) {
    print("\(title): \(counts.values.reduce(0, +))")
    for (key, count) in counts.sorted(by: { $0.key < $1.key }) { print("  \(key): \(count)") }
}
lines("work objects by type", report.objectsByType)
lines("machines by folder", report.machinesByFolder)
print("notes made projects: \(report.notes)")
print("facts: \(report.facts), filed: \(report.factsFiled)")
lines("facts by how filed", report.factsByHow)
lines("facts with no home, by task", report.factsUnfiledByTask)
