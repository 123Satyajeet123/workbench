import AppKit
import CaptureService
import EditorHarness
import Foundation
import Kernel
import LocalSources
import PageSnapshot

@testable import WorkbenchCore
@testable import WorkbenchUI

private final class QuietNotifier: Notifier {
    func authorize() async -> SystemAccess { .allowed }
    func post(title: String, body: String, page: SidebarSelection) async throws {}
}

/// The founder-like case as the app draws it: a machine that started with the first form, nine invented people with
/// long names and 58 invented facts, the native header and the document, off screen.
@MainActor
enum WholePage {
    static func run(into folder: URL) async throws -> [String] {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "whole-page-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let store = try Store(directory: scratch)
        let owner = try PersonID("whole-page-owner")
        guard let template = GalleryTemplate.of(id: MachineTemplate.team.id),
            let machine = try store.start(template, name: "Pip").machine
        else { throw DemoFailure("no machine") }
        _ = try seed(InventedTeam.facts(), in: store, of: machine, owner: owner, scope: "whole")
        let crew = Crew(
            store: store, capture: try CaptureService(store: store, owner: .success(owner)), founder: { "Rhea" },
            makeModel: nil, notifier: QuietNotifier(), owner: .success(owner),
            whatsAppContainer: scratch.appending(path: "no-whatsapp"))
        guard let helper = crew.helper(id: machine.id), let page = helper.pageModel else {
            throw DemoFailure("the machine has no page model")
        }
        let models = ModelSettings(store: store, secrets: MemorySecrets())
        var lines: [String] = []
        for width in [700.0, 1000.0] {
            for dark in [false, true] {
                let file = try await snapshot(
                    pageOf: page, subtitle: "Team chats", crew: crew, models: models, named: "final-team-\(Int(width))",
                    dark: dark, size: CGSize(width: width, height: 2400), in: folder)
                lines.append(file.lastPathComponent)
            }
        }
        return lines
    }
}
