import EditorHarness
import Foundation
import GRDB
import Kernel

@testable import PageSnapshot
@testable import WorkbenchCore
@testable import WorkbenchUI

/// Typed things in the document: headings that name structure, chips of settings, the head that cannot be deleted, a
/// field that waits for the person to leave it, a request line, and the answer to a proposal.
extension Behaviour {
    @MainActor
    private static func set(_ editor: OffscreenEditor, _ selector: String, _ value: String, at index: Int = 0)
        async throws
    {
        try await editor.run(
            "const n = document.querySelectorAll('\(selector)')[\(index)]; n.value = \(String(reflecting: value)); n.dispatchEvent(new Event('change', { bubbles: true }));"
        )
    }

    @MainActor
    private static func settle(_ desk: PageDesk) async throws {
        guard await desk.page.editor?.flush() == true else { throw DemoFailure("the editor did not settle") }
        try await Task.sleep(for: .milliseconds(400))
    }

    private static func blocks(_ desk: PageDesk) throws -> [FactsView] {
        let page = try desk.store.queries.page(of: desk.machine.page!, for: PageViewer(owner: desk.owner)).page
        return page.order.compactMap { place in
            if case .machine(let id) = place, case .facts(let view)? = page.blocks[id] { view } else { nil }
        }
    }

    /// A heading that names a field replaces the view with no model call; one that names nothing keeps the words and a note.
    static func headings() async throws -> String {
        let (desk, editor) = try await openDocument(ownerKnown: true)
        defer { desk.close() }
        let runs = try count(desk, "run")
        let before = try blocks(desk)
        guard let target = before.firstIndex(where: { $0.groupBy != nil }),
            let field = ["owes", "kind"].lazy.map { $0 as String }.first(where: { $0 != before[target].groupBy })
        else { throw DemoFailure("no view to retitle: \(before.map(\.title))") }
        try await set(editor, ".title-input", "By \(field.localizedUppercase)", at: target)
        try await settle(desk)
        let after = try blocks(desk)
        guard after[target].groupBy == field, after[target].title == "By \(field.localizedUppercase)",
            try count(desk, "run") == runs
        else {
            throw DemoFailure(
                "group \(after[target].groupBy ?? "nil"), title \(after[target].title), runs \(runs) -> \(try count(desk, "run"))"
            )
        }
        try await set(editor, ".title-input", "Late promises", at: target)
        try await settle(desk)
        let kept = try blocks(desk)[target]
        let note = try await editor.json(
            "return [...document.querySelectorAll('.machine-facts > .machine-line')].map(n => n.textContent).join('|')")
        guard kept.title == "Late promises", kept.groupBy == after[target].groupBy, note.contains("did not understand")
        else { throw DemoFailure("title \(kept.title), note \(note)") }
        return
            "\"By \(field.localizedUppercase)\" grouped by \(field) with 0 model calls (run rows \(runs) -> \(runs)); \"Late promises\" stays as the heading with the note \(note)"
    }

    /// A chip edit changes the stored record and nothing else; a value out of range or not a number is refused with the reason.
    static func chips() async throws -> String {
        let (desk, editor) = try await openDocument(ownerKnown: true)
        defer { desk.close() }
        let spec = desk.helper.spec
        let rows = ["machine_change", "machine_block", "evidence"]
        let outside = try rows.map { try count(desk, $0) }
        let was = desk.helper.watch
        try await set(editor, ".setting-chip", "30", at: 0)
        try await settle(desk)
        var expected = was
        expected.everyMinutes = 30
        guard desk.helper.watch == expected else {
            throw DemoFailure("watch \(desk.helper.watch), expected \(expected)")
        }
        guard try rows.map({ try count(desk, $0) }) == outside, desk.helper.spec == spec else {
            throw DemoFailure("a chip edit changed more than the record")
        }
        var refusals: [String] = []
        for (index, bad) in [(0, "9999"), (0, "soon"), (1, "22"), (2, "7")] {
            try await set(editor, ".setting-chip", bad, at: index)
            try await settle(desk)
            let note = try await editor.json(
                "return [...document.querySelectorAll('.sentence-note')].map(n => n.textContent).join('|')")
            guard desk.helper.watch == expected, note.contains("Nothing changed") else {
                throw DemoFailure("\(bad): watch \(desk.helper.watch), note \(note)")
            }
            refusals.append(note)
        }
        return "every 30 minutes stored; refused with the stored record unchanged: \(refusals.joined(separator: " / "))"
    }

    /// The machine on/off chip pauses the machine, and Undo takes a change back.
    static func switchAndUndo() async throws -> String {
        let (desk, editor) = try await openDocument(ownerKnown: true)
        defer { desk.close() }
        try await editor.run("document.querySelectorAll('.chip-menu')[0].open = true")
        try await editor.run(
            "[...document.querySelectorAll('.chip-option')].find(n => n.textContent === 'off').click()")
        try await settle(desk)
        guard desk.helper.isPaused else { throw DemoFailure("the machine is not paused") }
        try await editor.run(
            "[...document.querySelectorAll('.machine-action')].find(n => n.textContent === 'Undo').click()")
        try await settle(desk)
        guard !desk.helper.isPaused else { throw DemoFailure("Undo did not switch it back on") }
        return "chip off paused the machine; Undo switched it on again"
    }

    /// A deleted head block comes back at once; a field is sent when the person leaves it, not while they type.
    static func headAndBlur() async throws -> String {
        let (desk, editor) = try await openDocument(ownerKnown: true)
        defer { desk.close() }
        try await editor.run("window.wbEditor.removeBlocks(['document.title'])")
        guard try await editor.waitUntil("return document.querySelector('.field-title') !== null", seconds: 5)
        else { throw DemoFailure("the title did not come back") }
        try await editor.run("window.wbEditor.setTextCursorPosition('document.title', 'end'); window.wbEditor.focus();")
        editor.insertText(" Slow")
        try await Task.sleep(for: .milliseconds(900))
        let early = desk.helper.name
        try await editor.run("document.activeElement.blur()")
        try await Task.sleep(for: .milliseconds(900))
        guard early == "Follow-ups", desk.helper.name == "Follow-ups Slow" else {
            throw DemoFailure("while typing \(early), after leaving \(desk.helper.name)")
        }
        return
            "deleted title came back; name stayed \"\(early)\" for 900 ms of typing and became \"\(desk.helper.name)\" on leaving the field"
    }

    /// A line that starts with /ask is a request, not a paragraph; Accept and Decline sit in the proposed blocks.
    static func askAndDecide() async throws -> String {
        let (desk, editor) = try await openDocument(ownerKnown: true)
        defer { desk.close() }
        try await editor.run(
            "window.wbEditor.setTextCursorPosition('\(desk.paragraphs[1].rawValue)', 'end'); window.wbEditor.focus();")
        editor.insertText("\n/ask add a table of promises")
        editor.key("\r", code: 36)
        try await Task.sleep(for: .milliseconds(900))
        let stored = try desk.store.queries.noteBlocks(of: NoteID(object: desk.machine.page!)!).map(\.text)
        guard !stored.contains(where: { $0.contains("/ask") }) else {
            throw DemoFailure("the request line was kept: \(stored)")
        }
        try desk.proposeAChange()
        desk.page.refresh()
        guard
            try await editor.waitUntil(
                "return document.querySelector('.machine[data-standing=\"added\"] .machine-action') !== null")
        else { throw DemoFailure("no Accept or Decline in the proposed block") }
        try await editor.run(
            "document.querySelector('.machine[data-standing=\"added\"] .machine-action:nth-of-type(2)').click()")
        guard
            try await editor.waitUntil(
                "return document.querySelector('.machine[data-standing=\"added\"]') === null && !document.body.textContent.includes('Cassandra waits')"
            )
        else { throw DemoFailure("Decline left the proposal") }
        try desk.proposeAChange()
        desk.page.refresh()
        _ = try await editor.waitUntil(
            "return document.querySelector('.machine[data-standing=\"added\"] .machine-action') !== null")
        try await editor.run("document.querySelector('.machine[data-standing=\"added\"] .machine-action').click()")
        guard try await editor.waitUntil("return document.body.textContent.includes('Cassandra waits')") else {
            throw DemoFailure("Accept did not keep it")
        }
        return "the /ask line left no paragraph in the store; Decline cleared the proposal; Accept kept it"
    }
}
