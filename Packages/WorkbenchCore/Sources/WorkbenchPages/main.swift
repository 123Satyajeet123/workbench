import Foundation
import WorkbenchCore

// The native messaging host the Workbench browser extension calls. The browser starts it, writes framed messages to
// stdin and reads one framed reply per message from stdout. WORKBENCH_STORE names another store folder, for tests.
let folder =
    ProcessInfo.processInfo.environment["WORKBENCH_STORE"].map { URL(filePath: $0) }
    ?? URL.applicationSupportDirectory.appending(path: "Workbench")
let input = FileHandle.standardInput.readDataToEndOfFile()
do {
    let store = try Store(directory: folder)
    FileHandle.standardOutput.write(PageHost.receive(input, store: store))
} catch {
    FileHandle.standardOutput.write(PageHost.Reply(kept: false, error: "\(error)").framed)
    exit(1)
}
