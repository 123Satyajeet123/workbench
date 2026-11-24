import AppKit
import EditorHarness
import Foundation

@testable import WorkbenchUI

// Draws the candidate forms of a machine's page, off screen, on invented data, and runs the readability checks of
// every layout at its extremes. No window is shown. Usage: view-stress [expression-folder]
setvbuf(stdout, nil, _IOLBF, 0)
NSApplication.shared.setActivationPolicy(.prohibited)
let folder = URL(
    filePath: CommandLine.arguments.dropFirst().first { !$0.hasPrefix("--") }
        ?? "/Users/jeet/Projects/worktrace/plans/2026-11-25-machine-one-program/shots/expression")

func check(_ name: String, _ work: () async throws -> [String]) async {
    do {
        let lines = try await work()
        print("PASS \(name)")
        for line in lines { print("     \(line)") }
    } catch {
        print("FAIL \(name): \(error)")
        exit(1)
    }
}

await check("rules of the gate and of the first form") { try Rules.run() + Rules.firstForms() }
await check("the first form starts untouched pages and leaves touched ones") { try await StartRules.run() }
await check("the view bar offers what the gate allows, and stores a choice as the person's edit") {
    try await ViewBarCheck.run()
}
await check("the whole page: the document alone") { try await WholePage.run(into: folder) }
await check("every layout at its extremes, 700 pt wide") { try await Stress.run(into: folder) }
await check("the plain table: 2, 3 and 6 columns, a long cell, a long word") { try await PlainTable.run(into: folder) }
for set in [Sets.team, Sets.deals, Sets.news] {
    await check("pictures of \(set.name)") { try await Expression.render(set, into: folder) }
}
await check("no window on screen") {
    let windows = windowsOnScreen()
    guard windows.isEmpty else { throw DemoFailure("windows on screen: \(windows)") }
    return ["CGWindowListCopyWindowInfo(onScreenOnly) lists \(windows.count) windows of this process (pid \(getpid()))"]
}
print("ALL OK")
