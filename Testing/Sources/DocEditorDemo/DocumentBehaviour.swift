import EditorHarness
import Foundation
import GRDB
import Kernel

@testable import PageSnapshot
@testable import WorkbenchCore
@testable import WorkbenchUI

private final class Scripted: StructuredModel, Sendable {
    let name = "scripted"

    func generate<T: Decodable & Sendable>(_ type: T.Type, schema: JSONSchema, instructions: String, input: String)
        async throws -> ModelAnswer<T>
    {
        ModelAnswer(
            value: try JSONDecoder().decode(T.self, from: Data(#"{"items":[]}"#.utf8)), model: name, usage: Usage(),
            reply: "")
    }
}

/// The machine's page as one document: its title and job are fields, its status is a block, and with no owner the page
/// opens, says why and writes nothing.
extension Behaviour {
    @MainActor
    private static func openDocument(ownerKnown: Bool) async throws -> (desk: PageDesk, editor: OffscreenEditor) {
        let desk = try await PageDesk(ownerKnown: ownerKnown)
        desk.page.openEditor(appearance: .light, reduceMotion: false, scale: 1)
        guard let host = desk.page.editor?.host else { throw DemoFailure("the page did not open its editor") }
        let editor = OffscreenEditor(host: host, dark: false)
        guard
            try await editor.waitUntil(
                "return document.querySelectorAll('.field').length === 2 && document.querySelector('.machine-status, .machine-line')"
            )
        else {
            throw DemoFailure(
                "the document did not show its head: \(try await editor.json("return document.body.innerText"))")
        }
        return (desk, editor)
    }

    private static func count(_ desk: PageDesk, _ table: String) throws -> Int {
        try desk.store.queries.reader.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM \(table)") ?? 0 }
    }

    private static func instructions(_ machine: Machine, _ store: Store) -> String {
        HelperReader(spec: machine.spec, model: RecordedModel(Scripted(), store: store)).instructions
    }

    @MainActor
    private static func type(_ words: String, into field: String, _ desk: PageDesk, _ editor: OffscreenEditor)
        async throws
    {
        try await editor.run("window.wbEditor.setTextCursorPosition('\(field)', 'end'); window.wbEditor.focus();")
        editor.insertText(words)
        guard await desk.page.editor?.flush() == true else { throw DemoFailure("the editor did not settle") }
        try await Task.sleep(for: .milliseconds(300))
    }

    /// The document starts with the title, the job and the status, and an owner makes it editable.
    static func documentHead() async throws -> String {
        let (desk, editor) = try await openDocument(ownerKnown: true)
        defer { desk.close() }
        let order = try await editor.json(
            "return [...document.querySelectorAll('.bn-block-content')].slice(0, 3).map(n => n.dataset.contentType)")
        let editable = try await editor.json("return window.wbEditor.isEditable")
        let title = try await editor.json("return document.querySelector('.field-title .field-text').textContent")
        guard order.contains("field"), editable == "true", title.contains(desk.helper.name) else {
            throw DemoFailure("order \(order), editable \(editable), title \(title)")
        }
        return "first blocks \(order); title \(title); editable \(editable)"
    }

    /// Editing the title renames the machine; editing the job writes one machine_change row and keeps the prompt.
    static func titleAndJob() async throws -> String {
        let (desk, editor) = try await openDocument(ownerKnown: true)
        defer { desk.close() }
        let changes = try count(desk, "machine_change WHERE machine_id = \(desk.machine.id)")
        let promptBefore = instructions(desk.helper.machine, desk.store)
        try await type(" Two", into: "document.title", desk, editor)
        let renamed = try desk.store.queries.machines().first { $0.id == desk.machine.id }
        guard renamed?.name == "Follow-ups Two" else { throw DemoFailure("name is \(renamed?.name ?? "nil")") }
        let afterTitle = try count(desk, "machine_change WHERE machine_id = \(desk.machine.id)")
        try await type(" for my team", into: "document.job", desk, editor)
        let edited = try desk.store.queries.machines().first { $0.id == desk.machine.id }
        let afterJob = try count(desk, "machine_change WHERE machine_id = \(desk.machine.id)")
        guard edited?.spec.job?.hasSuffix(" for my team") == true, afterJob == afterTitle + 1 else {
            throw DemoFailure("job \(edited?.spec.job ?? "nil"), rows \(afterTitle) -> \(afterJob)")
        }
        guard instructions(edited!, desk.store) == promptBefore else { throw DemoFailure("the prompt changed") }
        return
            "title edit renamed to \(renamed!.name) (\(afterTitle - changes) row); job edit wrote \(afterJob - afterTitle) row; prompt bytes equal"
    }

    /// Without an owner the page opens, says why in its first lines and writes nothing.
    static func noOwner() async throws -> String {
        let (desk, editor) = try await openDocument(ownerKnown: false)
        defer { desk.close() }
        let tables = ["machine_change", "machine_block", "evidence", "page_proposal", "container_order"]
        let before = try tables.map { try count(desk, $0) }
        let editable = try await editor.json("return window.wbEditor.isEditable")
        let notice = try await editor.json("return document.querySelector('.machine-notice')?.textContent ?? ''")
        try await Task.sleep(for: .seconds(1))
        let after = try tables.map { try count(desk, $0) }
        guard editable == "false", notice.contains("read-only"), before == after else {
            throw DemoFailure("editable \(editable), notice \(notice), rows \(before) -> \(after)")
        }
        return "opens with a plain line (\(notice)); editable false; row counts \(after) unchanged"
    }
}
