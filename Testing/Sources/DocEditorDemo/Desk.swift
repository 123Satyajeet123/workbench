import Foundation
import GRDB
import Kernel
import Lines

@testable import WorkbenchCore
@testable import WorkbenchUI

/// A machine and its page in a new store in a temporary folder, with synthetic words only. Nothing here reads the
/// person's store, the network or the Keychain.
@MainActor
final class Desk {
    static let paragraphTexts = ["Budget talk with Asha.", "Next steps are unclear.", "Ravi owes the numbers."]

    let folder = FileManager.default.temporaryDirectory.appending(path: "doc-editor-\(UUID().uuidString)")
    private(set) var store: Store
    let owner: PersonID
    let machine: Machine?
    let pageObject: WorkObjectID
    let paragraphs: [BlockID]
    private(set) var machineBlocks: [MachineBlockID] = []

    var page: WorkObjectID { pageObject }
    var note: NoteID { NoteID(object: page)! }

    /// A machine's page holding `texts` as its paragraphs.
    init(texts: [String] = Desk.paragraphTexts) async throws {
        let store = try Store(directory: folder)
        let owner = try PersonID("editor-owner")
        let work = try store.createWorkObject(type: ObjectTypes.folder, parent: nil, name: "Follow-ups (synthetic)")
        let machine = try store.createMachine(from: .followUps, name: "Follow-ups", in: work.id)
        self.machine = machine
        pageObject = machine.page!
        self.store = store
        self.owner = owner
        paragraphs = try await Self.save(texts, on: pageObject, in: store, owner: owner)
    }

    /// A plain page that no machine owns, holding `texts`.
    init(plainPage texts: [String]) async throws {
        let store = try Store(directory: folder)
        let owner = try PersonID("editor-owner")
        pageObject = try store.createWorkObject(type: ObjectTypes.page, parent: nil, name: "Notes (synthetic)").id
        machine = nil
        self.store = store
        self.owner = owner
        paragraphs = try await Self.save(texts, on: pageObject, in: store, owner: owner)
    }

    /// Saves lines as paragraphs the way the old native editor did: one plain line each, in order.
    @discardableResult
    static func save(_ texts: [String], on page: WorkObjectID, in store: Store, owner: PersonID) async throws
        -> [BlockID]
    {
        let blocks = texts.map { _ in BlockID() }
        guard !blocks.isEmpty else { return blocks }
        try await store.saveNote(
            NoteChange(
                note: NoteID(object: page)!, blocks: zip(blocks, texts).map { NoteBlock(id: $0.0, text: $0.1) },
                endings: [], order: blocks), owner: owner)
        return blocks
    }

    /// A store opened again on the same folder: what a restart of the app gives.
    func reopen() throws { store = try Store(directory: folder) }

    func close() { try? FileManager.default.removeItem(at: folder) }

    /// Two blocks of the machine, as a proposal makes them and the person accepts them: a heading after the first
    /// paragraph, and a line that cites the second paragraph after the second.
    func addMachineBlocks(_ blocks: [(MachineBlock, after: PageBlockRef?)]) throws {
        let current = try store.queries.page(of: page, for: PageViewer(owner: owner))
        let gate = PageGate(catalog: PageCatalog(spec: machine!.spec, items: []))
        let (proposed, verdicts) = gate.apply(
            blocks.map { PageOperation.insert($0.0, after: $0.after) }, to: current.page)
        let run = try store.beginRun(
            task: PageComposer.task, model: "synthetic", prompt: "by hand", input: "no model call",
            kinds: [.typed, .note],
            window: try store.queries.pageGrounds(of: page, items: []).window(of: current.page, items: []))
        try store.finishRun(run, model: "synthetic", usage: Usage(), reply: "")
        let id = try store.propose(
            PageProposal(note: "By hand.", verdicts: verdicts, page: proposed, run: run), on: page, by: machine!.id,
            request: "Show a summary", owner: owner)
        try store.accept(proposal: id, surface: .machinePage)
        machineBlocks = try store.queries.page(of: page, for: PageViewer(owner: owner)).page.order.compactMap {
            if case .machine(let id) = $0 { id } else { nil }
        }
    }

    /// Everything the store holds for the page, as one string: the checks compare it before and after.
    func fingerprint() throws -> String {
        try store.queries.reader.read { db in
            let lines = try Row.fetchAll(db, sql: "SELECT count(*) AS n, max(id) AS last FROM evidence")
            let order = try String.fetchAll(
                db, sql: "SELECT hex(entity_key) FROM container_order WHERE container = ? ORDER BY position",
                arguments: [note.rawValue])
            let blocks = try Row.fetchAll(db, sql: "SELECT id, state, spec FROM machine_block ORDER BY id")
            return "\(lines)|\(order)|\(blocks)"
        }
    }
}
