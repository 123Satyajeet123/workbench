import EditorHarness
import Foundation
import GRDB
import Kernel
import Lines

@testable import WorkbenchCore

/// The first form on a real store, both directions: a page that nobody touched is started or restarted, and a page
/// that anybody touched is left as it is. Scratch stores, invented words, no model.
enum StartRules {
    static func run() async throws -> [String] {
        var lines: [String] = []
        let folder = FileManager.default.temporaryDirectory.appending(path: "start-rules-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        guard let template = GalleryTemplate.of(id: MachineTemplate.team.id) else { throw DemoFailure("no template") }
        let oldBlock = try startView(of: template)

        func machine(_ name: String) throws -> (Store, Machine) {
            let store = try Store(directory: folder.appending(path: name))
            guard let made = try store.start(template, name: "Pip").machine else { throw DemoFailure("no machine") }
            return (store, made)
        }
        func rows(_ store: Store, _ machine: Machine) throws -> [String] {
            try store.writer.read { db in
                try Row.fetchAll(
                    db,
                    sql:
                        "SELECT state, made_by_run, proposal_id FROM machine_block WHERE object_id = ? ORDER BY made_at, rowid",
                    arguments: [machine.page]
                ).map { "\($0["state"] as String)\(($0["made_by_run"] as Int64?) == nil ? "" : "+run")" }
            }
        }
        /// The page as the first version of the start left it: one live template block, no run, no proposal.
        func oldPage(_ name: String) throws -> (Store, Machine) {
            let (store, made) = try machine(name)
            let page = made.page!
            try store.writer.write { db in
                try db.execute(
                    sql: "DELETE FROM container_order WHERE container = ?", arguments: [try Store.container(of: page)])
                try db.execute(sql: "DELETE FROM machine_block WHERE object_id = ?", arguments: [page])
                let id = MachineBlockID()
                let key = try EntityKey.machineBlock(objectID: page, blockID: id.rawValue)
                try db.execute(
                    sql:
                        "INSERT INTO machine_block(id, object_id, entity_key, kind, spec, state, made_at) VALUES (?,?,?,?,?,'live',?)",
                    arguments: [
                        id.rawValue, page, Data(key.bytes), "facts", try Coding.json(MachineBlock.facts(oldBlock)),
                        store.clock().stored,
                    ])
                try EvidenceStamp.replaceOrder(of: try Store.container(of: page), with: [Data(key.bytes)], in: db)
            }
            return (store, made)
        }
        func expect(_ ok: Bool, _ what: String) throws { if !ok { throw DemoFailure(what) } }
        func titles(_ store: Store, _ machine: Machine) throws -> [String] {
            let page = try store.queries.page(of: machine.page!, for: PageViewer(owner: try PersonID("start-owner")))
                .page
            return page.order.compactMap { place in
                if case .machine(let id) = place, case .facts(let view)? = page.blocks[id] { view.title } else { nil }
            }
        }

        let (newStore, fresh) = try machine("new")
        try expect(
            try titles(newStore, fresh) == ["Needs you", "By person", "By project"],
            "a new machine does not start with the first form")
        try expect(
            try rows(newStore, fresh) == ["live", "live", "live"],
            "a new machine's blocks are not three live rows with no run")
        lines.append(
            "new machine: \(try titles(newStore, fresh).joined(separator: " / ")); rows \(try rows(newStore, fresh))")

        let (oldStore, old) = try oldPage("old")
        try expect(try titles(oldStore, old) == [oldBlock.title], "the old page is not the single template block")
        try oldStore.startPage(of: old)
        try expect(
            try titles(oldStore, old) == ["Needs you", "By person", "By project"],
            "the untouched page was not restarted")
        try expect(
            try rows(oldStore, old) == ["replaced", "live", "live", "live"], "the old block was not kept as replaced")
        try oldStore.startPage(of: old)
        try oldStore.startPage(of: old)
        try expect(try rows(oldStore, old).count == 4, "a second start is not idempotent")
        lines.append("untouched old page: board replaced, rows \(try rows(oldStore, old)); two more starts add nothing")

        let (paragraphStore, withParagraph) = try oldPage("paragraph")
        let note = NoteID(object: withParagraph.page!)!
        let block = BlockID()
        try await paragraphStore.saveNote(
            NoteChange(
                note: note, blocks: [NoteBlock(id: block, text: "A paragraph of the person.")], endings: [],
                order: [block]),
            owner: try PersonID("start-owner"))
        try paragraphStore.startPage(of: withParagraph)
        try expect(
            try titles(paragraphStore, withParagraph) == [oldBlock.title],
            "a page with a paragraph of the person was changed")
        lines.append("old page with a paragraph of the person: left as it is")

        let (removedStore, removed) = try oldPage("removed")
        let removedID = try removedStore.queries.page(
            of: removed.page!, for: PageViewer(owner: try PersonID("start-owner"))
        ).page.blocks.keys.first!
        try removedStore.removeBlock(removedID, surface: .machinePage)
        try removedStore.startPage(of: removed)
        try expect(
            try titles(removedStore, removed).isEmpty && (try rows(removedStore, removed)) == ["removed"],
            "a removed block came back")
        lines.append("old page whose block the person removed: stays removed, rows \(try rows(removedStore, removed))")

        let (editedStore, edited) = try oldPage("edited")
        let editedID = try editedStore.queries.page(
            of: edited.page!, for: PageViewer(owner: try PersonID("start-owner"))
        ).page.blocks.keys.first!
        var changed = oldBlock
        changed.layout = .list
        try editedStore.replaceBlock(editedID, with: .facts(changed))
        try editedStore.startPage(of: edited)
        try expect(
            try rows(editedStore, edited) == ["replaced", "live"],
            "a block the person changed was replaced by the start")
        lines.append("old page whose view the person changed: left as it is, rows \(try rows(editedStore, edited))")

        let (addedStore, added) = try oldPage("added")
        try await addedStore.writer.write { db in
            let page = added.page!
            let id = MachineBlockID()
            _ = try addedStore.insertLive(.heading("A heading the person kept"), as: id, on: page, in: db)
        }
        try addedStore.startPage(of: added)
        try expect(try rows(addedStore, added) == ["live", "live"], "a page with a second block was changed")
        lines.append("old page with a second block: left as it is")
        return lines
    }

    private static func startView(of template: GalleryTemplate) throws -> FactsView {
        guard let view = template.startFactsView(of: .team) else { throw DemoFailure("no start view") }
        return view
    }
}
