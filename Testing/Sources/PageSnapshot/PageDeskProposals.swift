import Foundation
import Kernel
import Lines

@testable import WorkbenchCore
@testable import WorkbenchUI

extension PageDesk {
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
        let old = try store.queries.page(of: machine.page!, for: PageViewer(owner: owner)).page.order.compactMap {
            place -> MachineBlockID? in if case .machine(let id) = place { id } else { nil }
        }
        try propose(
            old.map(PageOperation.remove) + [
                .insert(.heading("Open follow-ups"), after: .note(first)), .insert(.facts(view), after: .note(first)),
                .insert(.text(sentence), after: .note(second)), .insert(.grid(amounts), after: .note(second)),
                .insert(.picker(.whatsappChats), after: nil),
                .insert(.text(CitedText(text: "Ravi is late again.", cites: [])), after: nil),
            ], note: "Here is a view of your follow-ups, a line about Asha, and what was promised.")
    }

    /// A change to a page that holds blocks: a new line, the first heading put in new words, and the grid taken out.
    func proposeAChange() throws {
        let stored = try store.queries.page(of: machine.page!, for: PageViewer(owner: owner)).page
        let heading = stored.order.compactMap { place -> MachineBlockID? in
            if case .machine(let id) = place, case .heading? = stored.blocks[id] { id } else { nil }
        }.first
        let grid = stored.order.compactMap { place -> MachineBlockID? in
            if case .machine(let id) = place, case .grid? = stored.blocks[id] { id } else { nil }
        }.first
        var operations: [PageOperation] = [
            .insert(
                .text(CitedText(text: "Cassandra waits for the plan before the Tuesday call.", cites: [.request])),
                after: .note(paragraphs[1]))
        ]
        if let heading { operations.append(.update(heading, .heading("What is open this week"))) }
        if let grid { operations.append(.remove(grid)) }
        try propose(operations, note: "A new line, a clearer heading, and the table of amounts taken out.")
    }

    /// The caret in the empty paragraph at the end of the page, and a slash typed there: the slash menu opens.
    func openSlashMenu() async throws {
        guard let host = page.editor?.host else { throw RenderFailure("the page has no editor") }
        _ = try await host.webView.callAsyncJavaScript(
            "const e = window.wbEditor; e.setTextCursorPosition(e.document.at(-1), 'end'); e.focus();", arguments: [:],
            in: nil, contentWorld: .page)
        WebInput(webView: host.webView).key("/", code: 44)
        try await Task.sleep(for: .milliseconds(400))
    }
}
