import Foundation
import GRDB
import Kernel
import Lines

@testable import WorkbenchCore

extension World {
    func contents(for viewer: PageViewer? = nil) throws -> PageContents {
        try store.queries.page(of: page, for: viewer ?? reader)
    }

    func rows(_ sql: String) throws -> String {
        try store.writer.read { db in try String.fetchAll(db, sql: sql).joined(separator: " ") }
    }

    func blockIDs(_ kind: MachineBlockKind, in contents: PageContents) -> [MachineBlockID] {
        contents.page.order.compactMap { place -> MachineBlockID? in
            if case .machine(let id) = place, contents.page.blocks[id]?.kind == kind { id } else { nil }
        }
    }

    /// A proposal made by hand, the way the composer makes one: the gate checks the operations, and a run records
    /// the lines the machine was shown.
    @discardableResult
    func propose(_ operations: [PageOperation], note: String) throws -> PageProposalID {
        let current = try contents().page
        let (proposed, verdicts) = PageGate(catalog: PageCatalog(spec: machine.spec, items: facts)).apply(
            operations, to: current)
        if let refusal = verdicts.compactMap(\.refusal).first { throw DemoFailure("the gate refused: \(refusal)") }
        let grounds = try store.queries.pageGrounds(of: page, items: facts)
        let run = try store.beginRun(
            task: PageComposer.task, model: "synthetic", prompt: "by hand", input: "no model call",
            kinds: [.typed, .note], window: grounds.window(of: current, items: facts))
        try store.finishRun(run, model: "synthetic", usage: Usage(), reply: "")
        return try store.propose(
            PageProposal(note: note, verdicts: verdicts, page: proposed, run: run), on: page, by: machine.id,
            request: "Show my open follow-ups", owner: owner)
    }

    func saveParagraphs(
        _ blocks: [NoteBlock], endings: [BlockEnding], order: [BlockID], pageOrder: [PageBlockRef]? = nil
    ) async throws {
        try await store.saveNote(
            NoteChange(note: note, blocks: blocks, endings: endings, order: order, pageOrder: pageOrder),
            owner: owner)
    }

    func show(_ title: String, _ contents: PageContents) { print("\(title): \(describe(contents))") }
}

enum MachinePageDemo {
    static func run() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "machine-page-demo-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let world = try await World.make(in: directory)
        try checkCoding()
        try await world.walk()
        try await PageOrderCases.run(in: directory)
    }

    private static func checkCoding() throws {
        let blocks: [MachineBlock] = [
            .heading("Open"), .text(CitedText(text: "Words.", cites: [.fact(7), .note(BlockID()), .request])),
            .facts(
                FactsView(title: "View", filters: ["owes": ["you"]], groupBy: "kind", layout: .board, columns: ["who"])),
            .grid(Grid(title: "Sums", columns: ["A", "B"], rows: [["1", "=A1+1"]], cites: [.request])),
            .picker(.mailLabel),
        ]
        for block in blocks {
            try expect(try Coding.value(MachineBlock.self, from: Coding.json(block)), block, "spec round trip")
        }
        print("spec of a text block: \(try Coding.json(blocks[1]))")
        let operations: [StoredOperation] = [
            .insert(MachineBlockID(), after: .note(BlockID())), .insert(MachineBlockID(), after: nil),
            .replace(MachineBlockID(), with: MachineBlockID()), .remove(MachineBlockID()),
        ]
        try expect(
            try Coding.value([StoredOperation].self, from: Coding.json(operations)), operations, "ops round trip")
    }
}

extension World {
    func walk() async throws {
        let (p1, p2, p3) = (paragraphs[0], paragraphs[1], paragraphs[2])
        let asha = facts[0].id!
        try expect(describe(try contents()), "p1 p2 p3", "the page starts with the paragraphs")

        // A new proposal discards the pending one; the request is one typed evidence line; the run records its window.
        try propose([.insert(.heading("Stale"), after: nil)], note: "A first try.")
        let sentence = CitedText(text: "Asha waits for the deck.", cites: [.fact(asha), .note(p2)])
        let view = FactsView(
            title: "Open follow-ups", filters: ["owes": ["you"]], layout: .table, columns: ["who", "text", "quote"])
        let main = try propose(
            [
                .insert(.heading("Open follow-ups"), after: .note(p1)), .insert(.facts(view), after: .note(p1)),
                .insert(.text(sentence), after: .note(p2)), .insert(.picker(.whatsappChats), after: nil),
            ], note: "A view, a line and a picker.")
        try expect(try rows("SELECT state FROM page_proposal ORDER BY id"), "discarded pending", "one pending proposal")
        try expect(try rows("SELECT CAST(count(*) AS TEXT) FROM machine_block"), "4", "the old blocks were deleted")
        try expect(
            try rows(
                """
                SELECT e.text || '|' || e.actor || '|' || e.grant_id FROM page_proposal p
                JOIN evidence e ON e.line_id = p.request_line WHERE p.id = \(main)
                """), "Show my open follow-ups|me|typed:request", "the request is a typed evidence line")
        guard let pending = try store.queries.pendingProposal(of: page, for: reader) else {
            throw DemoFailure("no pending proposal")
        }
        try expect(pending.id, main, "the pending proposal")
        try expect(try store.queries.window(of: pending.run).count, 5, "the run window holds 3 paragraphs and 2 quotes")
        show("before accept", try contents())
        for operation in pending.operations { print("  pending: \(describe(operation, in: pending))") }

        try store.accept(proposal: main, surface: .machinePage)
        let accepted = try contents()
        show("after accept", accepted)
        try expect(describe(accepted), "p1 h(Open follow-ups) facts p2 text p3 picker", "accept puts blocks in place")
        try expect(try store.queries.pendingProposal(of: page, for: reader) == nil, true, "nothing is pending")
        try expect(
            try rows("SELECT state || ' ' || surface FROM page_proposal WHERE id = \(main)"), "accepted machine_page",
            "accept records the surface")
        let text = blockIDs(.text, in: accepted)[0]
        try expect(
            try rows(
                """
                SELECT group_concat(CASE WHEN item_id IS NULL THEN 'line' ELSE 'fact ' || quote_start || '-' || quote_end END, ' ')
                FROM (SELECT * FROM machine_block_cite WHERE block_id = '\(text.rawValue)' ORDER BY position)
                """), "fact \(facts[0].quoteSpan!.start)-\(facts[0].quoteSpan!.end) line", "cites of a text block")
        try expect(
            describe(try contents(for: stranger)), "p1 facts p2 p3 picker", "a reader the label refuses gets no words")

        // The person's own edits of machine blocks.
        let picker = blockIDs(.picker, in: accepted)[0]
        try store.moveBlock(picker, after: .note(p1))
        try expect(describe(try contents()), "p1 picker h(Open follow-ups) facts p2 text p3", "a block moves")
        try store.moveBlock(picker, after: .note(p3))

        // A place is rebased at accept time: p2 will be joined into p1 and p3 deleted before the proposal is accepted.
        let rebase = try propose(
            [.insert(.heading("Joined"), after: .note(p2)), .insert(.heading("Gone"), after: .note(p3))],
            note: "Two headings.")
        try await saveParagraphs(
            [NoteBlock(id: p1, text: "\(Self.paragraphTexts[0]) \(Self.paragraphTexts[1])")],
            endings: [.merged(p2, into: p1), .deleted(p3)], order: [p1])
        let merged = try contents()
        show("after merge of p2 into p1 and delete of p3", merged)
        try expect(
            describe(merged), "p1 h(Open follow-ups) facts text picker",
            "machine blocks follow the paragraph that holds the words")
        try store.accept(proposal: rebase, surface: .machinePage)
        let rebased = try contents()
        show("after accept of the rebased proposal", rebased)
        try expect(
            describe(rebased), "p1 h(Joined) h(Open follow-ups) facts text picker h(Gone)",
            "a joined place is followed, a gone place is last")

        // A block that replaces another one, a block the person removes, and a block still pending.
        let first = blockIDs(.text, in: rebased)[0]
        let revised = CitedText(text: "Asha waits for the deck, due Friday.", cites: [.fact(asha)])
        let replace = try propose([.update(first, .text(revised))], note: "A clearer line.")
        try store.accept(proposal: replace, surface: .machinePage)
        let replaced = try contents()
        try expect(describe(replaced), describe(rebased), "a replacing block takes the place of the old one")
        try expect(blockIDs(.text, in: replaced)[0] != first, true, "the new block has its own id")
        let extra = try propose(
            [.insert(.text(CitedText(text: "The deck is the first ask.", cites: [.fact(asha)])), after: nil)],
            note: "One more line.")
        try store.accept(proposal: extra, surface: .machinePage)
        try store.removeBlock(blockIDs(.text, in: try contents()).last!, surface: .machinePage)
        let pendingLine = try propose(
            [.insert(.text(CitedText(text: "Asha asked for the deck.", cites: [.fact(asha)])), after: nil)],
            note: "A second line on Asha.")
        try expect(
            try rows("SELECT group_concat(state, ' ') FROM (SELECT state FROM machine_block ORDER BY rowid)"),
            "live live replaced live live live live removed proposed", "states of blocks before the erase")

        // Erase the one line that Asha's fact quotes: every block built on it loses its words, in every state.
        try store.eraseEvidence(EvidenceErasure(messageRefs: ["L1"]))
        let erased = try contents()
        show("after erase of line L1", erased)
        try expect(
            describe(erased), "p1 h(Joined) h(Open follow-ups) facts text* picker h(Gone)",
            "the live block lost its words")
        try expect(
            try rows(
                "SELECT group_concat(kind || ':' || state || ':' || words_erased, ' ') FROM (SELECT * FROM machine_block ORDER BY rowid)"
            ),
            "heading:live:0 facts:live:0 text:replaced:1 picker:live:0 heading:live:0 heading:live:0 text:live:1 text:removed:1 text:proposed:1",
            "which blocks lost their words")
        try expect(
            try rows(
                "SELECT group_concat(CASE WHEN note = '' THEN 'empty' ELSE 'kept' END, ' ') FROM (SELECT note FROM page_proposal ORDER BY id)"
            ),
            "kept empty kept empty empty empty", "which notes were emptied")
        guard let still = try store.queries.pendingProposal(of: page, for: reader) else {
            throw DemoFailure("the pending proposal is gone")
        }
        try expect(still.id, pendingLine, "the pending proposal stays")
        try expect(still.note, "", "its note was emptied")
        try expect(still.blocks.values.map(\.kind), [.text], "its block stays")
        try expect(
            still.blocks.values.first, MachineBlock.text(CitedText(text: "", cites: [.fact(asha)])),
            "its words were emptied")

        // An archived page leaves the tree and keeps what is on it, as it keeps its notes.
        let before = describe(try contents())
        try store.archive(page)
        try expect(describe(try contents()), before, "an archived page keeps its blocks")
        try expect(
            try rows("SELECT removed_surface FROM machine_block WHERE removed_surface IS NOT NULL"), "machine_page",
            "a block the person removed has the surface")
    }
}
