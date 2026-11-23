import AppKit
import Foundation
import SwiftUI

@testable import WorkbenchCore
@testable import WorkbenchUI

// Draws the machine's page to PNGs in four states and two appearances, on synthetic data in a temporary folder, with no
// model call. Usage: machine-page-render [png-folder]
setvbuf(stdout, nil, _IOLBF, 0)
_ = NSApplication.shared
let defaultFolder = "/Users/jeet/Projects/worktrace/plans/2026-11-24-machine-page/shots"
let shots = URL(filePath: CommandLine.arguments.dropFirst().first ?? defaultFolder)
let size = CGSize(width: 1000, height: 1400)

do {
    let desk = try await Desk()
    defer { desk.close() }

    func draw(_ name: String) async throws {
        for dark in [false, true] {
            let page = Page(title: desk.page.name, subtitle: "Follow-ups") { MachinePageView(model: desk.page) }
                .environment(desk.crew).environment(ModelSettings(store: desk.store, secrets: MemorySecrets()))
            print(try await snapshot(page, named: name, dark: dark, size: size, in: shots).path)
        }
    }

    desk.page.refresh()
    try await draw("a-new-page")
    try await desk.acceptAnOldHeading()
    try desk.proposeTheFullPage()
    try await draw("b-pending-proposal")
    await desk.page.accept()
    try await draw("c-after-accept")
    try await desk.eraseSecondParagraph()
    try await draw("d-after-erase")
} catch {
    print("FAILED: \(error)")
    exit(1)
}
