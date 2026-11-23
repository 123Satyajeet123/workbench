import Foundation
import Kernel
import Lines

@testable import WorkbenchCore
@testable import WorkbenchUI

extension Desk {
    /// A proposal made by hand with the Pages types, as the composer makes one, and kept as the page keeps it. The
    /// gate checks the operations, and a run records the lines the machine was shown.
    func propose(_ operations: [PageOperation], note: String) throws {
        let contents = try store.queries.page(of: machine.page!, for: PageViewer(owner: owner))
        let gate = PageGate(catalog: PageCatalog(spec: machine.spec, items: facts))
        let (proposed, verdicts) = gate.apply(operations, to: contents.page)
        let grounds = try store.queries.pageGrounds(of: machine.page!, items: facts)
        let run = try store.beginRun(
            task: PageComposer.task, model: "synthetic", prompt: "by hand", input: "no model call",
            kinds: [.typed, .note], window: grounds.window(of: contents.page, items: facts))
        try store.finishRun(run, model: "synthetic", usage: Usage(), reply: "")
        try page.submit(
            PageProposal(note: note, verdicts: verdicts, page: proposed, run: run), asked: "Show my open follow-ups")
    }

    /// One heading the person has accepted, which the next proposal takes out.
    func acceptAnOldHeading() async throws {
        try propose([.insert(.heading("Notes from last week"), after: nil)], note: "A heading.")
        await page.accept()
    }

    /// A heading, a list of the facts, a line that cites a fact and a paragraph, a grid with a total, a picker, and one
    /// change that cites nothing, which the gate refuses.
    func proposeTheFullPage() throws {
        let (first, second) = (paragraphs[0], paragraphs[1])
        let view = FactsView(title: "Open follow-ups", layout: .list)
        let sentence = CitedText(
            text: "Asha waits for the deck, and the plan is still unclear.",
            cites: [.fact(facts[0].id!), .note(second)])
        let amounts = WorkbenchCore.Grid(
            title: "What was promised", columns: ["Item", "Amount"],
            rows: [["The deck", "120"], ["The numbers", "80"], ["Total", "=SUM(B1:B2)"]], cites: [.request])
        let old = page.shown.order.compactMap { place -> MachineBlockID? in
            if case .machine(let id) = place { id } else { nil }
        }
        try propose(
            old.map(PageOperation.remove) + [
                .insert(.heading("Open follow-ups"), after: .note(first)), .insert(.facts(view), after: .note(first)),
                .insert(.text(sentence), after: .note(second)), .insert(.grid(amounts), after: .note(second)),
                .insert(.picker(.whatsappChats), after: nil),
                .insert(.text(CitedText(text: "Ravi is late again.", cites: [])), after: nil),
            ], note: "Here is a view of your follow-ups, a line about Asha, and what was promised.")
    }

    /// The person deletes the second paragraph, which the line cites: its words and the copies are erased.
    func eraseSecondParagraph() async throws {
        try await store.saveNote(
            NoteChange(
                note: NoteID(object: machine.page!)!, blocks: [], endings: [.deleted(paragraphs[1])],
                order: [paragraphs[0]]), owner: owner)
        page.refresh()
    }
}
