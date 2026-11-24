import AppKit
import Foundation

// Runs the machine page's own model against a private copy of the synthetic demo store: ask, accept, discard, remove
// and reopen, with the real model for each ask and a PNG drawn offscreen after each step. No window is shown.
// Usage: machine-page-live [png-folder] [resume]
setvbuf(stdout, nil, _IOLBF, 0)
_ = NSApplication.shared
let shotsFolder =
    CommandLine.arguments.dropFirst().first
    ?? "/Users/jeet/Projects/worktrace/plans/2026-11-24-machine-page/shots/live-model"
let resumesAtSentences = CommandLine.arguments.dropFirst(2).first == "resume"
let demoFolder = URL.applicationSupportDirectory.appending(path: "Workbench Demo")
let copyFolder = URL(filePath: "/private/tmp/claude-501/wbd6b/Workbench Demo")

do {
    let demo = try DemoCopy(from: demoFolder, to: copyFolder)
    defer { demo.delete() }
    let shots = URL(filePath: shotsFolder)
    let expected = try await Walk(session: LiveSession(folder: demo.folder), shots: shots).run(
        resumesAtSentences: resumesAtSentences)
    try await Walk(session: LiveSession(folder: demo.folder), shots: shots).reopened(equalTo: expected)
    print("\nALL OK")
} catch {
    print("\(error)")
    exit(1)
}
