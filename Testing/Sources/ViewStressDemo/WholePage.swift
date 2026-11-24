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

private struct OwnerLost: LocalizedError {
    var errorDescription: String? { "Workbench could not open the name it keeps for you in the Keychain." }
}

/// The page as the app draws it: a machine's document and nothing around it, off screen. A team machine with nine
/// invented people with long names, a machine that rates, and a Mac whose Keychain cannot name its owner.
@MainActor
enum WholePage {
    private struct Case {
        var name: String
        var start: (Store) throws -> Machine
        var facts: [InventedFact]
        var ownerKnown = true
    }

    static func run(into folder: URL) async throws -> [String] {
        let team = { (store: Store) -> Machine in
            guard let template = GalleryTemplate.of(id: MachineTemplate.team.id),
                let machine = try store.start(template, name: "Pip").machine
            else { throw DemoFailure("no machine") }
            return machine
        }
        let deals = { (store: Store) -> Machine in
            let work = try store.createWorkObject(type: ObjectTypes.folder, parent: nil, name: "Deals (synthetic)")
            var spec = HelperSpec.dealIntake
            spec.source = .whatsAppChat
            return try store.createMachine(from: spec, name: "Deals", in: work.id)
        }
        var lines: [String] = []
        for scene in [
            Case(name: "team", start: team, facts: InventedTeam.facts()),
            Case(name: "rating", start: deals, facts: InventedDeals.facts()),
            Case(name: "no-owner", start: team, facts: InventedTeam.facts(), ownerKnown: false),
        ] {
            lines += try await render(scene, into: folder)
        }
        return lines
    }

    private static func render(_ scene: Case, into folder: URL) async throws -> [String] {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "whole-page-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let store = try Store(directory: scratch)
        let owner = try PersonID("whole-page-owner")
        let machine = try scene.start(store)
        _ = try seed(scene.facts, in: store, of: machine, owner: owner, scope: "whole")
        let crew = Crew(
            store: store, capture: try CaptureService(store: store, owner: .success(owner)), founder: { "Rhea" },
            makeModel: nil, notifier: QuietNotifier(),
            owner: scene.ownerKnown ? .success(owner) : .failure(OwnerLost()),
            whatsAppContainer: scratch.appending(path: "no-whatsapp"))
        guard let helper = crew.helper(id: machine.id), let page = helper.pageModel else {
            throw DemoFailure("the machine has no page model")
        }
        let models = ModelSettings(store: store, secrets: MemorySecrets())
        var lines: [String] = []
        for width in [700.0, 1000.0] {
            for dark in [false, true] {
                let file = try await snapshot(
                    pageOf: page, crew: crew, models: models, named: "\(scene.name)-\(Int(width))", dark: dark,
                    size: CGSize(width: width, height: 2400), in: folder)
                lines.append(file.lastPathComponent)
            }
        }
        return lines
    }
}
