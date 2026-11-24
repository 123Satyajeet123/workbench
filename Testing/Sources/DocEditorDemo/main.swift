import AppKit
import EditorHarness
import Foundation

@testable import WorkbenchUI

// Checks the document editor with no window on screen, on scratch stores and synthetic words.
// Usage: doc-editor [--update-contract] [shots-folder]
setvbuf(stdout, nil, _IOLBF, 0)
NSApplication.shared.setActivationPolicy(.prohibited)
let arguments = Array(CommandLine.arguments.dropFirst())
let shots = URL(
    filePath: arguments.first { !$0.hasPrefix("--") }
        ?? "/Users/jeet/Projects/worktrace/plans/2026-11-25-machine-one-program/shots/editor-swap")

func check(_ name: String, _ work: () async throws -> String) async {
    do { print("PASS \(name): \(try await work())") } catch {
        print("FAIL \(name): \(error)")
        exit(1)
    }
}

await check("contract") {
    try ContractCheck().run(update: arguments.contains("--update-contract")).joined(separator: "; ")
}
await check("round trip with no ops") { try await Checks.roundTrip() }
await check("typing, composition, restart") { try await Checks.typing() }
await check("Backspace joins, erases nothing") { try await Checks.merge() }
await check("erase of a line empties its block") { try await Checks.erase() }
await check("machine insert during a composition") { try await Checks.compositionWithInsert() }
await check("injected markup and remote loads") { try await Checks.injection() }
await check("style-src-attr on a join") { try await Behaviour.styleViolationOnMerge() }
await check("block shortcuts") { try await Behaviour.shortcuts() }
await check("slash menu") { try await Behaviour.slashMenu() }
await check("Tab nests") { try await Behaviour.nesting() }
await check("undo across blocks") { try await Behaviour.undo() }
await check("block menu") { try await Behaviour.blockMenu() }
await check("move past a machine block") { try await Behaviour.moveAcrossMachine() }
await check("marks round trip") { try await Behaviour.marks() }
await check("placeholder") { try await Behaviour.placeholder() }
await check("proposal: new, replacing, removed; accept; discard") { try await Behaviour.proposal() }
await check("marks from the editor equal the card's") { try await Behaviour.marksParity() }
await check("failed write is tried again") { try await Behaviour.failedWrite() }
await check("page written by the old native editor") { try await Behaviour.oldNativePage() }
await check("plain page") { try await Behaviour.plainPage() }
await check("page height") { try await Behaviour.height() }
await check("size") { try await Behaviour.size() }
await check("pictures") { try await Checks.pictures(in: shots).joined(separator: ", ") }
await check("no window on screen") {
    let windows = windowsOnScreen()
    guard windows.isEmpty else { throw DemoFailure("windows on screen: \(windows)") }
    return "CGWindowListCopyWindowInfo(onScreenOnly) lists \(windows.count) windows of this process (pid \(getpid()))"
}
print("ALL OK")
