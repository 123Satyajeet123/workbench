import AppKit
import Foundation
import GRDB
import Kernel

@testable import WorkbenchCore
@testable import WorkbenchUI

/// The page as a person writes in it: shortcuts, menus, nesting, undo, marks, and the placeholder. Each check drives
/// the editor through its own commands and through the text input and key calls the keyboard makes.
extension Session {
    /// A new empty paragraph at the end of the page, with the caret in it.
    func newParagraph() async throws {
        try await editor.run(
            """
            const e = window.wbEditor;
            const [made] = e.insertBlocks([{type: 'paragraph'}], e.document.at(-1), 'after');
            e.setTextCursorPosition(made, 'start'); e.focus();
            """)
    }

    /// The type of the block with the caret.
    func caretType() async throws -> String {
        try await editor.json("return window.wbEditor.getTextCursorPosition().block.type")
    }

    func caretBlock() async throws -> String {
        try await editor.json(
            "const b = window.wbEditor.getTextCursorPosition().block; return {type: b.type, props: b.props, depth: window.wbEditor.getTextCursorPosition().parentBlock ? 1 : 0}"
        )
    }

    func pause(_ milliseconds: Int = 600) async throws { try await Task.sleep(for: .milliseconds(milliseconds)) }
}

enum Behaviour {
    /// `# `, `- `, `1. `, `[] ` and `> ` typed at the start of an empty paragraph turn it into that block.
    static func shortcuts() async throws -> String {
        let desk = try await Checks.standardDesk()
        defer { desk.close() }
        let session = try await Session(desk: desk)
        var found: [String] = []
        for (typed, type) in [
            ("# ", "heading"), ("- ", "bulletListItem"), ("1. ", "numberedListItem"), ("[] ", "checkListItem"),
            ("> ", "quote"),
        ] {
            try await session.newParagraph()
            session.editor.insertText(typed)
            try await session.pause(150)
            session.editor.insertText("word")
            let got = try await session.caretType()
            guard got == "\"\(type)\"" else { throw DemoFailure("typing \"\(typed)\" gave \(got), not \(type)") }
            found.append("\"\(typed)\" -> \(type)")
        }
        try await session.settle()
        let stored = try session.storedWords().suffix(5)
        guard Array(stored) == ["# word", "- word", "1. word", "- [ ] word", "> word"] else {
            throw DemoFailure("stored lines are \(stored)")
        }
        return "\(found.joined(separator: "; ")); stored lines \(Array(stored))"
    }

    /// `/` opens the slash menu; the filter narrows it; Return inserts the chosen block.
    static func slashMenu() async throws -> String {
        let desk = try await Checks.standardDesk()
        defer { desk.close() }
        let session = try await Session(desk: desk)
        try await session.newParagraph()
        session.editor.key("/", code: 44)
        guard try await session.editor.waitUntil("return document.querySelector('.slash-menu:not([hidden])') !== null")
        else {
            let state = try await session.editor.json(
                "const b = window.wbEditor.getTextCursorPosition().block; return {text: JSON.stringify(b.content), panel: Boolean(document.querySelector('.slash-menu')), hidden: document.querySelector('.slash-menu')?.hidden, focused: window.wbEditor.isFocused(), active: document.activeElement?.className}"
            )
            throw DemoFailure("the slash menu did not open: \(state)")
        }
        let all = try await session.editor.json(
            "return [...document.querySelectorAll('.slash-menu .menu-title')].map(n => n.textContent)")
        session.editor.insertText("head")
        _ = try await session.editor.waitUntil(
            "return document.querySelectorAll('.slash-menu .menu-title').length < \(all.split(separator: ",").count)")
        let filtered = try await session.editor.json(
            "return [...document.querySelectorAll('.slash-menu .menu-title')].map(n => n.textContent)")
        session.editor.key("\r", code: 36)
        try await session.pause(300)
        let type = try await session.caretBlock()
        guard type.contains("\"heading\"") else { throw DemoFailure("Return chose \(type); menu was \(filtered)") }
        let closed = try await session.editor.json("return document.querySelector('.slash-menu').hidden")
        guard closed == "true" else {
            let state = try await session.editor.json(
                "return {text: JSON.stringify(window.wbEditor.getTextCursorPosition().block.content), rows: document.querySelectorAll('.slash-menu .menu-row').length}"
            )
            throw DemoFailure("the menu stayed open: \(state)")
        }
        session.editor.insertText("more words")
        try await session.pause(200)
        guard try await session.editor.json("return document.querySelector('.slash-menu').hidden") == "true" else {
            throw DemoFailure("the menu came back while typing after it closed")
        }
        return
            "menu opened with \(all); \"head\" narrowed it to \(filtered); Return turned the block into \(type); menu closed"
    }

    /// Tab puts a block under the one above it; the stored line is indented; Shift-Tab takes it back.
    static func nesting() async throws -> String {
        let desk = try await Checks.standardDesk()
        defer { desk.close() }
        let session = try await Session(desk: desk)
        try await session.place(desk.paragraphs[2])
        session.editor.key("\r", code: 36)
        session.editor.insertText("Child words")
        session.editor.key("\t", code: 48)
        try await session.settle()
        let depth = try await session.editor.json(
            "return window.wbEditor.getTextCursorPosition().parentBlock?.id ?? null")
        guard depth.contains(desk.paragraphs[2].rawValue) else {
            throw DemoFailure("Tab did not nest: parent \(depth)")
        }
        guard try session.storedWords().last == "| Child words" else {
            throw DemoFailure("stored line \(try session.storedWords().last ?? "none")")
        }
        try await session.editor.run("window.wbEditor.unnestBlock()")
        try await session.settle()
        guard try session.storedWords().last == "Child words" else {
            let state = try await session.editor.json(
                "const p = window.wbEditor.getTextCursorPosition(); return {parent: p.parentBlock?.id ?? null, canUnnest: window.wbEditor.canUnnestBlock(), text: JSON.stringify(p.block.content)}"
            )
            throw DemoFailure("unnest did not work: \(try session.storedWords()) \(state)")
        }
        return
            "Tab nested the block under the paragraph above (stored \"| Child words\"); the editor's unnest command put it back (stored \"Child words\")"
    }

    /// Cmd-Z takes back typing in the order it was done, across the blocks it touched.
    static func undo() async throws -> String {
        let desk = try await Checks.standardDesk()
        defer { desk.close() }
        let session = try await Session(desk: desk)
        try await session.place(desk.paragraphs[2])
        session.editor.insertText(" alpha")
        try await session.pause()
        session.editor.key("\r", code: 36)
        session.editor.insertText("beta")
        try await session.pause()
        let before = try await session.filled().count
        session.editor.key("z", code: 6, modifiers: .command)
        try await session.pause(200)
        let afterOne = try await session.filled()
        session.editor.key("z", code: 6, modifiers: .command)
        session.editor.key("z", code: 6, modifiers: .command)
        try await session.pause(200)
        let afterAll = try await session.filled()
        try await session.settle()
        guard try session.storedWords() == Desk.paragraphTexts else {
            throw DemoFailure("after undo the store holds \(try session.storedWords()); page \(afterAll)")
        }
        return
            "blocks with words: \(before) before undo, \(afterOne.count) after one Cmd-Z, \(afterAll.count) after the rest; stored lines equal the original \(Desk.paragraphTexts.count)"
    }

    /// The block menu: turn into, duplicate, delete, and remove for a machine block.
    static func blockMenu() async throws -> String {
        let desk = try await Checks.standardDesk()
        defer { desk.close() }
        let session = try await Session(desk: desk)
        let target = desk.paragraphs[1].rawValue
        func choose(_ title: String, on id: String) async throws {
            try await session.editor.run(
                """
                const box = document.querySelector('[data-id="\(id)"] .bn-block-content, [data-id="\(id)"] .machine').getBoundingClientRect();
                const at = {bubbles: true, clientX: box.left + 40, clientY: box.top + box.height / 2};
                document.querySelector('.bn-editor').dispatchEvent(new MouseEvent('mousemove', at));
                """)
            guard
                try await session.editor.waitUntil("return document.querySelector('.side-menu:not([hidden])') !== null")
            else { throw DemoFailure("the handle did not show beside the block") }
            try await session.editor.run("document.querySelector('.side-handle').click()")
            let clicked = try await session.editor.json(
                "const row = [...document.querySelectorAll('.block-menu .menu-row')].find(r => r.textContent === '\(title)'); if (row) { row.click(); } return Boolean(row)"
            )
            guard clicked == "true" else { throw DemoFailure("no menu row \"\(title)\"") }
            try await session.pause(200)
        }
        try await choose("Heading 2", on: target)
        try await session.settle()
        guard try session.storedWords().contains("## Next steps are unclear.") else {
            throw DemoFailure("turn into: \(try session.storedWords())")
        }
        try await choose("Duplicate", on: target)
        try await session.settle()
        let afterDuplicate = try session.storedWords().filter { $0 == "## Next steps are unclear." }.count
        guard afterDuplicate == 2 else { throw DemoFailure("duplicate gave \(afterDuplicate) copies") }
        try await choose("Delete", on: target)
        try await session.settle()
        let afterDelete = try session.storedWords().filter { $0 == "## Next steps are unclear." }.count
        guard afterDelete == 1 else { throw DemoFailure("delete left \(afterDelete) copies") }
        let machine = try await session.editor.json(
            "return [...document.querySelectorAll('.bn-block-outer')].filter(o => o.querySelector('.machine')).map(o => o.dataset.id)"
        )
        let machineID = try JSONDecoder().decode([String].self, from: Data(machine.utf8))[0]
        try await choose("Remove from page", on: machineID)
        try await session.settle()
        let remaining = try desk.store.queries.page(of: desk.page, for: PageViewer(owner: desk.owner)).page.blocks.count
        guard remaining == desk.machineBlocks.count - 1 else { throw DemoFailure("remove left \(remaining) blocks") }
        return
            "turn into Heading 2 stored \"## Next steps are unclear.\"; duplicate made 2 copies; delete left 1; Remove from page took a machine block out of the store (\(remaining) left of \(desk.machineBlocks.count))"
    }

    /// A block moved past a machine block lands there, and the stored order matches the editor's.
    static func moveAcrossMachine() async throws -> String {
        let desk = try await Checks.standardDesk()
        defer { desk.close() }
        let session = try await Session(desk: desk)
        let moved = desk.paragraphs[0].rawValue
        let before = try await session.shown()
        try await session.editor.run(
            """
            const e = window.wbEditor;
            const moved = e.getBlock('\(moved)');
            const machines = e.document.filter(b => b.type === 'machine');
            e.removeBlocks([moved]);
            e.insertBlocks([moved], machines.at(-1), 'after');
            """)
        try await session.settle()
        let shown = try await session.filled().map { String($0.split(separator: "|")[1]) }
        let stored = try desk.store.queries.page(of: desk.page, for: PageViewer(owner: desk.owner)).page.order.map {
            switch $0 {
            case .note(let id): id.rawValue
            case .machine(let id): id.rawValue
            }
        }
        guard shown == stored, stored.last == moved || stored.dropLast().last == moved else {
            throw DemoFailure("editor \(shown) but store \(stored)")
        }
        return
            "paragraph moved from index \(before.firstIndex { $0.contains(moved) } ?? -1) to \(stored.firstIndex(of: moved) ?? -1), after the last machine block; store order equals editor order (\(stored.count) blocks)"
    }

    /// Bold, italic, code and a link are stored as the line format and come back as the same marks.
    static func marks() async throws -> String {
        let desk = try await Checks.standardDesk()
        defer { desk.close() }
        let session = try await Session(desk: desk)
        try await session.newParagraph()
        session.editor.insertText("alpha beta gamma delta")
        func select(_ word: String) async throws {
            try await session.editor.run(
                """
                const e = window.wbEditor; let from = -1;
                e.prosemirrorState.doc.descendants((node, pos) => { if (node.type.name === 'paragraph' && node.textContent === 'alpha beta gamma delta') from = pos + 1 + node.textContent.indexOf('\(word)'); });
                if (from < 0) throw new Error('no word');
                e.transact(tr => tr.setSelection(tr.selection.constructor.create(tr.doc, from, from + \(word.count))));
                """)
        }
        try await select("beta")
        try await session.editor.run("window.wbEditor.toggleStyles({bold: true})")
        try await select("gamma")
        try await session.editor.run("window.wbEditor.toggleStyles({italic: true})")
        try await select("delta")
        try await session.editor.run("window.wbEditor.toggleStyles({code: true})")
        try await select("alpha")
        try await session.editor.run("window.wbEditor.createLink('https://example.com/a')")
        try await session.settle()
        let expected = "[alpha](https://example.com/a) *beta* _gamma_ `delta`"
        guard try session.storedWords().last == expected else {
            throw DemoFailure("stored \(try session.storedWords().last ?? "none")")
        }
        try desk.reopen()
        let again = try await Session(desk: desk)
        let content = try await again.editor.json(
            "return window.wbEditor.document.find(b => (JSON.stringify(b.content) || '').includes('alpha')).content.map(c => c.type === 'link' ? 'link:' + c.href + ':' + c.content.map(x => x.text).join('') : c.text + ':' + Object.keys(c.styles).join('+'))"
        )
        guard content.contains("link:https://example.com/a:alpha"), content.contains("beta:bold"),
            content.contains("gamma:italic"), content.contains("delta:code")
        else { throw DemoFailure("after restart the marks are \(content)") }
        return "stored line = \"\(expected)\"; after a restart the editor shows \(content)"
    }

    /// An empty document and an empty last paragraph show the hint, with no style element and no refused load.
    static func placeholder() async throws -> String {
        let desk = try await Desk(plainPage: [])
        defer { desk.close() }
        let session = try await Session(
            desk: desk, ready: "return window.wbEditor && document.querySelector('.bn-block-outer')")
        let shown = try await hint(session)
        guard shown == "\"Write, or type / for blocks\"" else { throw DemoFailure("an empty page shows \(shown)") }
        session.editor.insertText("Some words")
        try await session.newParagraph()
        session.editor.key("\r", code: 36)
        try await session.editor.run("window.wbEditor.blur()")
        try await session.pause(200)
        let trailing = try await hint(session)
        guard trailing == shown else { throw DemoFailure("the last empty paragraph shows \(trailing)") }
        let styles = try await session.editor.json(
            "return [document.querySelectorAll('style').length, document.querySelectorAll('[style]:not(.panel):not(.side-menu)').length]"
        )
        guard session.controller.blockedLoads.isEmpty else {
            throw DemoFailure("the policy refused: \(session.controller.blockedLoads)")
        }
        return
            "empty page and empty last paragraph (unfocused) both show \(shown) from ::after content: attr(data-hint); style elements and style attributes: \(styles); loads refused: 0"
    }

    private static func hint(_ session: Session) async throws -> String {
        try await session.editor.json(
            "const last = [...document.querySelectorAll('.bn-block-content[data-hint]')].at(-1); return last ? getComputedStyle(last, '::after').content.replace(/^\"|\"$/g, '') : null"
        )
    }
}

extension Behaviour {
    /// The Backspace key joins paragraphs through the editor's own key handling and the policy refuses nothing. The
    /// same join by the web view's own editing command, which no key press takes, makes WebKit try to put a style
    /// attribute on the joined block: the policy refuses that one attribute, none ever lands, and the joined line is right.
    static func styleViolationOnMerge() async throws -> String {
        var report: [String] = []
        for (name, join) in [
            ("Backspace key", { (editor: OffscreenEditor) in editor.key("\u{7F}", code: 51) }),
            ("deleteBackward: command", { (editor: OffscreenEditor) in editor.command("deleteBackward:") }),
        ] {
            let desk = try await Checks.standardDesk()
            defer { desk.close() }
            let session = try await Session(desk: desk)
            try await session.editor.run(
                """
                window.__csp = [];
                document.addEventListener('securitypolicyviolation', (e) => window.__csp.push([e.effectiveDirective, e.blockedURI, e.sample].join(' | ')));
                """)
            try await session.place(desk.paragraphs[2])
            session.editor.key("\r", code: 36)
            session.editor.insertText("Tail words")
            try await session.settle()
            try await session.editor.run(
                "const e = window.wbEditor; e.setTextCursorPosition(e.document.at(-1), 'start'); e.focus();")
            join(session.editor)
            try await session.settle()
            let seen = try await session.editor.json(
                "return [window.__csp, [...document.querySelectorAll('#page [style]')].length]")
            guard try session.storedWords().last == "Ravi owes the numbers.Tail words" else {
                throw DemoFailure("\(name): the join stored \(try session.storedWords())")
            }
            report.append(
                "\(name): joined line stored right, policy reports and style attributes left in the page = \(seen)")
        }
        return report.joined(separator: "; ")
    }
}
