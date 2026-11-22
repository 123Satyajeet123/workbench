import Foundation
import WorkbenchCore

let folder =
    ProcessInfo.processInfo.environment["WORKBENCH_STORE"].map { URL(filePath: $0) }
    ?? URL.applicationSupportDirectory.appending(path: "Workbench")
do {
    let store = try Store(directory: folder)
    PageHost.serve(
        read: { count in
            var data = Data()
            while data.count < count, let chunk = try? FileHandle.standardInput.read(upToCount: count - data.count),
                !chunk.isEmpty
            {
                data += chunk
            }
            return data
        }, write: { FileHandle.standardOutput.write($0) }, store: store)
} catch {
    FileHandle.standardOutput.write(PageHost.Reply(kept: false, error: "\(error)").framed)
    exit(1)
}
