import Foundation
import WorkbenchCore

// Counts what the move of old window stretches into the evidence store would write and refuse, on a copy of the store.
// Usage: ScreenBackfillDryRunTool <store folder>. The folder is a backup copy of the store. The tool prints counts only.
guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: ScreenBackfillDryRunTool <store folder>\n".utf8))
    exit(2)
}
let counts = try ScreenBackfillCounts.preview(onCopyOf: URL(filePath: CommandLine.arguments[1]))
print("closed stretches in the old rows: \(counts.stretches)")
print("would write: \(counts.written)")
print("would refuse, app not allowed now: \(counts.refusedConsent)")
