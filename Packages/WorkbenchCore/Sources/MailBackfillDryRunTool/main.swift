import Foundation
import WorkbenchCore

// Counts what the move of old mail rows into the evidence store would write and refuse, on a copy of the store. Usage:
// mail-backfill-dry-run <store folder>. The folder is a backup copy of the store. The tool prints counts only.
guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: mail-backfill-dry-run <store folder>\n".utf8))
    exit(2)
}
let counts = try MailBackfillCounts.preview(onCopyOf: URL(filePath: CommandLine.arguments[1]))
print("mail rows: \(counts.parts)")
print("would write: \(counts.written) (messages \(counts.messages), deck pages \(counts.deckPages))")
print("  sender known (group member): \(counts.senderKnown)")
print("  sender unknown (authority unknown): \(counts.senderUnknown)")
print("would refuse, label not allowed now: \(counts.refusedLabelNotAllowed)")
print("would refuse, no thread or message id: \(counts.refusedNoKey)")
