import CaptureService
import Foundation
import GRDB
import Kernel
import Lines
import LocalSources

@testable import WorkbenchCore
@testable import WorkbenchUI

/// A machine and its page in a new store in a temporary folder: two paragraphs, and nine facts from nine people with
/// long invented names, each quoting a line. Nothing here reads the person's store, the network or the Keychain.
@MainActor
final class PageDesk {
    static let scope = "render"
    static let paragraphTexts = ["Budget talk with Asha.", "Next steps are unclear."]
    static let people = [
        "Alexandria Montgomery-Fitzgerald Example", "Bartholomew Featherstonehaugh Example",
        "Cassandra Papadopoulos-Whitfield Example", "Dmitri Alexandrovich Rostropovich Example",
        "Eleanor Vanderbilt-Hargreaves Example", "Fitzwilliam Oyelaran-Nakamura Example",
        "Genevieve Abernathy-Castellanos Example", "Hildegard Zimmermann-Kowalczyk Example",
        "Ignatius Balasubramanian-Thorne Example",
    ]
    static let quotes = [
        "send me the deck by Friday", "send the numbers on Monday", "share the plan before the Tuesday call",
        "book the room for the Wednesday review", "confirm the budget with the finance team",
        "send the revised draft after lunch", "bring the printed copies to the meeting",
        "reply to the supplier before the weekend", "update the shared sheet with the new dates",
    ]
    static let sourceTexts = zip(people, quotes).map { "\($0): please \($1)" }

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
            fields: zip(people, quotes).enumerated().map { index, pair in
                [
                    "who": pair.0, "person": pair.0, "owes": index.isMultiple(of: 2) ? "you" : "them",
                    "kind": index.isMultiple(of: 2) ? "ask" : "promise", "text": "\(pair.0): \(pair.1)",
                ]
            })
    }
}

final class QuietNotifier: Notifier {
    func authorize() async -> SystemAccess { .allowed }
    func post(title: String, body: String, page: SidebarSelection) async throws {}
}
