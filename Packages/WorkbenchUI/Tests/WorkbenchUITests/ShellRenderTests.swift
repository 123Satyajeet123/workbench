import SwiftUI
import Testing

@testable import WorkbenchUI

/// The window shell drawn to PNG files for a person to look at. The folder comes from `SHELL_SHOTS_DIR`.
@MainActor @Suite(.serialized) struct ShellRenderTests {
    private static let size = CGSize(width: 1160, height: 760)

    private func shot(
        _ name: String, dark: Bool, size: CGSize = size, zoom: Double = 1, machines: [String] = [],
        template: TeamTemplate = .fund, setUp: (AppSession) -> Void = { _ in }
    ) async throws {
        let session = try await ShellFixture.session(template: template, extraMachines: machines)
        let shell = ShellWindow(session: session, size: size, zoom: zoom, dark: dark)
        shell.show(settle: 0.6)
        setUp(session)
        shell.settle(1.0)
        try shell.save("\(name)-\(dark ? "dark" : "light")")
    }

    @Test(arguments: [false, true]) func today(dark: Bool) async throws {
        try await shot("shell-today", dark: dark)
    }

    @Test(arguments: [false, true]) func aMachineSelected(dark: Bool) async throws {
        try await shot("shell-machine", dark: dark) { session in
            session.navigation.requested = .machine(session.crew.crew[0].machine.id)
        }
    }

    @Test(arguments: [false, true]) func aFactInThePanel(dark: Bool) async throws {
        try await shot("shell-panel", dark: dark) { session in
            session.navigation.show(fact: session.today.needs[1].item.id!)
        }
    }

    @Test(arguments: [false, true]) func theCommandPalette(dark: Bool) async throws {
        try await shot("shell-palette", dark: dark) { $0.navigation.isPaletteOpen = true }
    }

    @Test(arguments: [false, true]) func theSmallestWindow(dark: Bool) async throws {
        try await shot("shell-minimum", dark: dark, size: WorkbenchView.minimumSize)
    }

    @Test(arguments: [false, true]) func zoomedToOneAndAHalf(dark: Bool) async throws {
        try await shot("shell-zoom-1.5", dark: dark, zoom: 1.5)
    }

    @Test(arguments: [false, true]) func manyMachines(dark: Bool) async throws {
        try await shot("shell-many-machines", dark: dark, machines: (1...9).map { "Machine \($0)" })
    }

    @Test func aTeamWithNoDeals() async throws {
        try await shot("shell-no-deals", dark: false, template: .startupTeam)
    }
}
