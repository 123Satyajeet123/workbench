import CaptureService
import Foundation
import GRDB
import Kernel
import Lines
import LocalSources
import PageSnapshot

@testable import WorkbenchCore
@testable import WorkbenchUI

/// A machine and its page in a new store in a temporary folder: three paragraphs are not needed, two are, and two
/// facts quote two stored lines. Nothing here reads the person's store, the network or the Keychain.
@MainActor
final class Desk {
    static let scope = "render"
    static let paragraphTexts = ["Budget talk with Asha.", "Next steps are unclear."]
    static let sourceTexts = ["Asha: please send me the deck by Friday", "Ravi: I will send the numbers on Monday"]
    static let quotes = ["send me the deck by Friday", "send the numbers on Monday"]

    let folder = FileManager.default.temporaryDirectory.appending(path: "machine-page-render-\(UUID().uuidString)")
    let store: Store
    let owner: PersonID
    let crew: Crew
    let machine: Machine
    let helper: HelperModel
    let page: MachinePageModel
    let paragraphs: [BlockID]
    let facts: [Item]

    init() async throws {
        let store = try Store(directory: folder)
        let owner = try PersonID("render-owner")
        let work = try store.createWorkObject(type: ObjectTypes.folder, parent: nil, name: "Follow-ups (synthetic)")
        let machine = try store.createMachine(from: .followUps, name: "Follow-ups", in: work.id)
        guard let pageID = machine.page, let note = NoteID(object: pageID) else { throw RenderFailure("no page") }
        let paragraphs = Self.paragraphTexts.map { _ in BlockID() }
        try await store.saveNote(
            NoteChange(
                note: note, blocks: zip(paragraphs, Self.paragraphTexts).map { NoteBlock(id: $0.0, text: $0.1) },
                endings: [], order: paragraphs), owner: owner)
        let facts = try Self.makeFacts(in: store, of: machine, owner: owner)
        let crew = Crew(
            store: store, capture: try CaptureService(store: store, owner: .success(owner)), founder: { "Rhea" },
            makeModel: nil, notifier: QuietNotifier(), owner: .success(owner),
            whatsAppContainer: folder.appending(path: "no-whatsapp"))
        guard let helper = crew.helper(id: machine.id), let page = helper.pageModel else {
            throw RenderFailure("the machine has no page model")
        }
        (self.store, self.owner, self.crew, self.machine, self.helper, self.page) = (
            store, owner, crew, machine, helper, page
        )
        (self.paragraphs, self.facts) = (paragraphs, facts)
    }

    func close() { try? FileManager.default.removeItem(at: folder) }

    private static func makeFacts(in store: Store, of machine: Machine, owner: PersonID) throws -> [Item] {
        try saveSyntheticFacts(
            in: store, of: machine, owner: owner, scope: scope, sources: sourceTexts, quotes: quotes,
            fields: [
                ["who": "Asha", "owes": "you", "kind": "ask", "text": "Send Asha the deck by Friday"],
                ["who": "Ravi", "owes": "them", "kind": "promise", "text": "Ravi sends the numbers on Monday"],
            ])
    }
}

final class QuietNotifier: Notifier {
    func authorize() async -> SystemAccess { .allowed }
    func post(title: String, body: String, page: SidebarSelection) async throws {}
}
