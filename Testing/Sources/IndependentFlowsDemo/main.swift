import AppKit
import Foundation

@testable import WorkbenchCore
@testable import WorkbenchUI

// Shows the gates of step IND-1 on synthetic data. A scripted model, a fake search, a scratch store: no network, no
// Keychain, and never the store in ~/Library/Application Support/Workbench. Usage: independent-flows [png-folder]
setvbuf(stdout, nil, _IOLBF, 0)
_ = NSApplication.shared
let pngFolder = URL(filePath: CommandLine.arguments.dropFirst().first ?? "/tmp/independent-flows")
var failures = 0

func check(_ condition: Bool, _ words: String) {
    if !condition { failures += 1 }
    print("  \(condition ? "yes" : "NO ") \(words)")
}

func gate(_ name: String, _ body: () async throws -> Void) async {
    print("\n\(name)")
    do { try await body() } catch {
        failures += 1
        print("  NO  stopped: \(error)")
    }
}

await Gates.run(png: pngFolder)
print(failures == 0 ? "\nAll gates held." : "\n\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
