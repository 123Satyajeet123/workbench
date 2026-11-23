import Foundation
import WorkbenchCore

// Counts what the fact lifecycle step changes in a store, on a copy of it. Usage: lifecycle-dry-run <store folder>.
// The folder is a backup copy of the store. The tool prints counts and item ids only.
guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: lifecycle-dry-run <store folder>\n".utf8))
    exit(2)
}
let report = try LifecycleDryRun.run(onCopyOf: URL(filePath: CommandLine.arguments[1]))
print("items: \(report.items)")
print("events before the step: \(report.eventsBefore)")
print("items whose status changes: \(report.changes.count)")
for (reason, count) in report.byReason.sorted(by: { $0.key < $1.key }) { print("  \(reason): \(count)") }
for change in report.changes { print("  item \(change.item): \(change.was) -> \(change.now) (\(change.reason))") }
