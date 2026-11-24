import AppKit
import Foundation
import SwiftUI

@testable import PageSnapshot
@testable import WorkbenchCore
@testable import WorkbenchUI

// Draws the machine's page, header and document, to PNGs off screen: nine people with long invented names, at two
// widths in both appearances, then with the slash menu open and with a proposal that waits. It uses a temporary store,
// synthetic words and no model call. Usage: machine-page-render [png-folder]
setvbuf(stdout, nil, _IOLBF, 0)
_ = NSApplication.shared
let defaultFolder = "/Users/jeet/Projects/worktrace/plans/2026-11-25-machine-one-program/shots/editor-swap"
let shots = URL(filePath: CommandLine.arguments.dropFirst().first ?? defaultFolder)

do {
    let desk = try await PageDesk()
    defer { desk.close() }
    let models = ModelSettings(store: desk.store, secrets: MemorySecrets())

    func draw(_ name: String, width: CGFloat, dark: Bool, prepare: () async throws -> Void = {}) async throws {
        print(
            try await snapshot(
                pageOf: desk.page, crew: desk.crew, models: models, named: name, dark: dark,
                size: CGSize(width: width, height: 1700), in: shots, prepare: prepare
            ).path)
    }

    desk.page.refresh()
    try desk.proposeTheFullPage()
    await desk.page.accept()
    for width in [700.0, 1000.0] {
        for dark in [false, true] { try await draw("page-\(Int(width))", width: width, dark: dark) }
    }
    try await draw("slash-menu", width: 1000, dark: false) { try await desk.openSlashMenu() }
    try desk.proposeAChange()
    for dark in [false, true] { try await draw("pending-proposal", width: 1000, dark: dark) }
} catch {
    print("FAILED: \(error)")
    exit(1)
}
