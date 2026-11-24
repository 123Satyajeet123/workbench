import AppKit
import EditorHarness
import Foundation

@testable import WorkbenchCore
@testable import WorkbenchUI

// A blank machine, built from an empty workbench by typing: a source and a job in one sentence, and nothing else.
// Scratch stores, invented words, a scripted model, no network. Every picture is drawn off screen.
// Usage: blank-machine [shot-folder]
setvbuf(stdout, nil, _IOLBF, 0)
NSApplication.shared.setActivationPolicy(.prohibited)
let shots = URL(
    filePath: CommandLine.arguments.dropFirst().first { !$0.hasPrefix("--") }
        ?? "/Users/jeet/Projects/worktrace/plans/2026-11-25-machine-one-program/shots/blank-machine")

func finish() -> Never {
    heading("11. No window on screen")
    let windows = windowsOnScreen()
    check("\(windows.count) windows of this process on screen", windows.isEmpty)
    if failures.isEmpty {
        print("\nALL OK")
    } else {
        print("\nFAILED:\n" + failures.map { "  \($0)" }.joined(separator: "\n"))
        exit(1)
    }
    exit(0)
}

do {
    let scratch = try Scratch(named: "main")
    defer { scratch.remove() }
    try Empty.check(scratch, "0. An empty workbench")
    var files = try await Pages.home("home-empty", in: scratch, to: shots) + Pages.addSheet(in: scratch, to: shots)
    Sources.run()
    let machines = try Specs.makeOverEachSource(in: scratch)
    let rules = try Scratch(named: "rules")
    defer { rules.remove() }
    try Rules.run(in: rules)
    try await Reading.run(machines, in: scratch)
    try Pages.checkFirstForms(machines, in: scratch)
    if let whatsApp = machines.first(where: { $0.spec.source == .whatsAppChat }) {
        files += try await Pages.page(of: whatsApp, in: scratch, to: shots)
    }
    files += try await Pages.home("home-with-facts", in: scratch, to: shots)
    try Lifecycle.run(machines, in: scratch)
    try Empty.check(scratch, "7b. Empty again after the delete")
    try OldShape.run()
    try Gone.run()
    try Builtins.run(in: try Scratch(named: "builtins"))
    heading("Pictures")
    for file in files { print("  \(file.path)") }
} catch {
    print("FAIL: \(error)")
    exit(1)
}
finish()
