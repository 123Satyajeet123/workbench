import AppKit
import Foundation
import Kernel

@testable import WorkbenchCore
@testable import WorkbenchUI

/// One page in a scratch store with its editor in a window that is never shown.
@MainActor
struct Session {
    let desk: Desk
    let editor: OffscreenEditor
    let controller: PageEditorController

    init(desk: Desk, dark: Bool = false, facts: [Item] = []) async throws {
        self.desk = desk
        editor = OffscreenEditor(dark: dark)
        controller = try PageEditorController(
            store: desk.store, page: desk.page, owner: desk.owner, host: editor.host,
            appearance: dark ? .dark : .light, reduceMotion: false,
            views: { MachineViewBuilder(facts: facts, titleOf: { _ in "" }, pickerNote: { _ in nil }) })
        controller.start()
        guard
            try await editor.waitUntil(
                "return window.wbEditor && window.wbEditor.document.length > 1 && document.querySelector('.machine') !== null"
            )
        else {
            throw DemoFailure("the editor did not load the page")
        }
    }

    /// The page as the editor shows it: type, id and words of each block.
    func shown() async throws -> [String] {
        let text = try await editor.json(
            "return window.wbEditor.document.map(b => b.type + '|' + b.id + '|' + (b.content||[]).map(c=>c.text||'').join(''))"
        )
        return try JSONDecoder().decode([String].self, from: Data(text.utf8))
    }

    /// The blocks with words, and the machine blocks: the editor also holds an empty paragraph to write in.
    func filled() async throws -> [String] {
        try await shown().filter { !($0.hasPrefix("paragraph") && $0.hasSuffix("|")) }
    }

    func storedWords() throws -> [String] { try desk.store.queries.noteBlocks(of: desk.note).map(\.text) }

    func place(_ id: BlockID, at end: String = "end") async throws {
        try await editor.run(
            "window.wbEditor.setTextCursorPosition('\(id.rawValue)', '\(end)'); window.wbEditor.focus();")
    }

    func settle() async throws {
        try await Task.sleep(for: .milliseconds(250))
        guard await controller.flush() else { throw DemoFailure("the editor did not settle") }
    }
}

enum Checks {
    static func standardDesk() async throws -> Desk {
        let desk = try await Desk()
        try desk.addMachineBlocks([
            (.heading("Open follow-ups"), after: .note(desk.paragraphs[0])),
            (
                .text(CitedText(text: "Asha waits for the deck.", cites: [.note(desk.paragraphs[1])])),
                after: .note(desk.paragraphs[1])
            ),
        ])
        return desk
    }

    /// Load, no ops, save: nothing changes in the store.
    static func roundTrip() async throws -> String {
        let desk = try await standardDesk()
        defer { desk.close() }
        let before = try desk.fingerprint()
        let session = try await Session(desk: desk)
        try await session.settle()
        let shown = try await session.filled()
        let kinds = shown.map { String($0.split(separator: "|").first!) }
        guard kinds.filter({ $0 == "paragraph" }).count == 3,
            kinds.filter({ $0 == "machine" }).count == desk.machineBlocks.count,
            desk.machineBlocks.count >= 2
        else { throw DemoFailure("the page is not 3 paragraphs and the machine blocks: \(shown)") }
        guard try desk.fingerprint() == before, session.controller.storeWrites == 0 else {
            throw DemoFailure("the store changed with no ops")
        }
        return
            "3 paragraphs and \(desk.machineBlocks.count) machine blocks shown (\(kinds.joined(separator: ","))); store fingerprint equal before and after; store writes = \(session.controller.storeWrites)"
    }

    /// Typed text arrives as ops, is stored with stable ids, and a restart shows the same page.
    static func typing() async throws -> String {
        let desk = try await standardDesk()
        defer { desk.close() }
        let session = try await Session(desk: desk)
        let last = desk.paragraphs[2]
        try await session.place(last)
        try await session.editor.run(
            "window.wbEditor.insertInlineContent([{type:'text', text:' (API)', styles:{bold:true}}])")
        session.editor.insertText(" soon")
        for step in ["क", "कि", "किय"] { session.editor.markText(step) }
        session.editor.insertText("किया")
        for step in ["k", "か", "かん", "かんじ"] { session.editor.markText(step) }
        session.editor.insertText("漢字")
        session.editor.key("\r", code: 36)
        session.editor.insertText("New paragraph")
        try await session.settle()
        let stored = try desk.store.queries.noteBlocks(of: desk.note)
        let expected = "Ravi owes the numbers.* (API) soon\u{0915}\u{093F}\u{092F}\u{093E}漢字*"
        guard stored.map(\.text).last == "New paragraph", stored.dropLast().last?.text == expected,
            stored.dropLast().last?.id == last, stored.prefix(2).map(\.id) == Array(desk.paragraphs.prefix(2))
        else { throw DemoFailure("stored words are wrong: \(stored.map(\.text))") }
        let before = try await session.filled()
        let writes = try desk.fingerprint()
        try desk.reopen()
        let again = try await Session(desk: desk)
        try await again.settle()
        guard try await again.filled() == before else {
            throw DemoFailure("a restart shows another page")
        }
        guard try desk.fingerprint() == writes else { throw DemoFailure("a restart wrote to the store") }
        return
            "stored line = \"\(expected)\" under the id it had; new line stored; restart shows the same \(before.count) blocks and writes nothing"
    }

    /// Backspace joins a paragraph into the one before it; nothing is erased.
    static func merge() async throws -> String {
        let desk = try await standardDesk()
        defer { desk.close() }
        let session = try await Session(desk: desk)
        let last = desk.paragraphs[2]
        try await session.place(last)
        session.editor.key("\r", code: 36)
        session.editor.insertText("Tail words")
        try await session.settle()
        guard try session.storedWords().count == 4 else { throw DemoFailure("the new paragraph was not stored") }
        try await session.editor.run(
            "const e = window.wbEditor; e.setTextCursorPosition(e.document.at(-1), 'start'); e.focus();")
        session.editor.command("deleteBackward:")
        try await session.settle()
        let words = try session.storedWords()
        guard words.count == 3, words.last == "Ravi owes the numbers.Tail words" else {
            throw DemoFailure("merge stored \(words)")
        }
        return "after Backspace at the start: 3 lines, last = \"\(words.last!)\" (the joined line was kept, not erased)"
    }

    /// A deleted paragraph is erased with its line, and a machine block that rests on it is emptied.
    static func erase() async throws -> String {
        let desk = try await standardDesk()
        defer { desk.close() }
        let session = try await Session(desk: desk)
        let second = desk.paragraphs[1].rawValue
        try await session.editor.run("window.wbEditor.removeBlocks(['\(second)'])")
        try await session.settle()
        let contents = try desk.store.queries.page(of: desk.page, for: PageViewer(owner: desk.owner))
        guard try !session.storedWords().contains("Next steps are unclear."), contents.erased.count == 1 else {
            throw DemoFailure("the line was not erased or the block was not emptied")
        }
        let shown = try await session.editor.json(
            "return [...document.querySelectorAll('.machine')].map(n => n.className + ':' + n.textContent)")
        guard shown.contains(MachineViewBuilder.erasedNote) else {
            throw DemoFailure("the editor still shows the words: \(shown)")
        }
        guard try await !session.shown().joined().contains("Asha waits for the deck.") else {
            throw DemoFailure("the words of the emptied block are still in the editor")
        }
        return "line gone from the store; \(contents.erased.count) machine block flagged erased; editor shows \(shown)"
    }

    /// A machine block put in above the caret in the middle of a composition changes neither the caret nor the word.
    static func compositionWithInsert() async throws -> String {
        let desk = try await standardDesk()
        defer { desk.close() }
        let session = try await Session(desk: desk)
        let last = desk.paragraphs[2]
        try await session.place(last)
        for step in ["k", "か", "かん"] { session.editor.markText(step) }
        let caretBefore = try await session.editor.json("return window.wbEditor.getTextCursorPosition().block.id")
        try desk.addMachineBlocks([
            (.text(CitedText(text: "Inserted by the machine.", cites: [.request])), after: .note(desk.paragraphs[0]))
        ])
        try session.controller.refresh()
        guard
            try await session.editor.waitUntil("return document.body.textContent.includes('Inserted by the machine.')")
        else {
            throw DemoFailure("the machine block did not show")
        }
        session.editor.markText("かんじ")
        session.editor.insertText("漢字")
        let caretAfter = try await session.editor.json("return window.wbEditor.getTextCursorPosition().block.id")
        try await session.settle()
        let shown = try await session.shown()
        let target = shown.first { $0.contains(last.rawValue) } ?? ""
        let inserted = shown.first { $0.hasPrefix("machine") && $0.hasSuffix("|") } ?? ""
        guard caretBefore == caretAfter, target.hasSuffix("Ravi owes the numbers.漢字"), !inserted.contains("漢字"),
            try session.storedWords().last == "Ravi owes the numbers.漢字"
        else { throw DemoFailure("caret \(caretBefore) -> \(caretAfter); block \(target)") }
        return
            "caret block unchanged (\(caretAfter)); composed text \"漢字\" is in the person's paragraph and not in the machine block; stored line = \"\(try session.storedWords().last!)\""
    }

    /// Captured text with markup renders as text and runs nothing; the policy refuses a remote load.
    static func injection() async throws -> String {
        let desk = try await Desk()
        defer { desk.close() }
        let attack =
            "<script>window.__pwned = 1</script><img src=\"https://example.com/p.png\" onerror=\"window.__pwned = 2\">"
        try await desk.store.saveNote(
            NoteChange(
                note: desk.note, blocks: [NoteBlock(id: desk.paragraphs[0], text: attack)], endings: [],
                order: desk.paragraphs),
            owner: desk.owner)
        try desk.addMachineBlocks([
            (.text(CitedText(text: attack, cites: [.request])), after: .note(desk.paragraphs[0]))
        ])
        let session = try await Session(desk: desk)
        try await session.settle()
        let scripts = try await session.editor.json(
            "return [document.querySelectorAll('#page script').length, document.querySelectorAll('#page img:not(.ProseMirror-separator)').length, typeof window.__pwned, document.getElementById('page').textContent.split('<script>').length - 1]"
        )
        guard scripts == "[0,0,\"undefined\",2]" else { throw DemoFailure("markup became elements or ran: \(scripts)") }
        let before = session.controller.blockedLoads.count
        try await session.editor.run(
            """
            const img = document.createElement('img'); img.src = 'https://example.com/remote.png'; document.body.append(img);
            const script = document.createElement('script'); script.src = 'https://example.com/remote.js'; document.body.append(script);
            try { await fetch('https://example.com/fetch'); } catch (error) {}
            try { eval('1'); } catch (error) {}
            """)
        try await Task.sleep(for: .milliseconds(500))
        let refused = session.controller.blockedLoads.dropFirst(before).compactMap { message -> String? in
            if case .blocked(let directive, let uri) = message { "\(directive) \(uri)" } else { nil }
        }
        guard refused.contains(where: { $0.hasPrefix("img-src") }),
            refused.contains(where: { $0.hasPrefix("script-src") }),
            refused.contains(where: { $0.hasPrefix("connect-src") }),
            refused.contains(where: { $0.hasPrefix("script-src") && $0.contains("eval") })
        else { throw DemoFailure("a remote load was not refused: \(refused)") }
        return
            "2 markup strings drawn as text (0 script, 0 img, no sentinel); refused: \(refused.joined(separator: "; "))"
    }

    /// The page, drawn in both appearances, with every kind of machine block.
    static func pictures(in folder: URL) async throws -> [String] {
        var files: [String] = []
        for dark in [false, true] {
            let desk = try await Desk()
            defer { desk.close() }
            try desk.addMachineBlocks(richBlocks(desk))
            let facts = Self.facts()
            let session = try await Session(desk: desk, dark: dark, facts: facts)
            try await session.editor.run("document.querySelector('.machine-facts .fact')?.classList.add('shot')")
            try await Task.sleep(for: .milliseconds(600))
            let file = folder.appending(path: "page-\(dark ? "dark" : "light").png")
            try await session.editor.png(to: file)
            files.append(file.path)
        }
        return files
    }

    private static func richBlocks(_ desk: Desk) -> [(MachineBlock, after: PageBlockRef?)] {
        let (first, second) = (desk.paragraphs[0], desk.paragraphs[1])
        return [
            (.heading("Open follow-ups"), .note(first)),
            (.facts(FactsView(title: "Open follow-ups", layout: .list)), .note(first)),
            (
                .text(
                    CitedText(
                        text: "Asha waits for the deck, and the plan is still unclear.",
                        cites: [.note(second), .request])), .note(second)
            ),
            (
                .grid(
                    WorkbenchCore.Grid(
                        title: "What was promised", columns: ["Item", "Amount"],
                        rows: [["The deck", "120"], ["The numbers", "80"], ["Total", "=SUM(B1:B2)"]], cites: [.request])
                ), .note(second)
            ),
            (.picker(.whatsappChats), nil),
        ]
    }

    private static func facts() -> [Item] {
        let day = WorkDay(containing: Date())
        return [("Asha", "send me the deck by Friday"), ("Ravi", "send the numbers on Monday")].enumerated().map {
            index, pair in
            Item(
                id: Int64(index + 1), task: "follow-ups", day: day, scope: "demo", source: .whatsapp, citeFirst: 1,
                citeLast: 1,
                start: Date(), end: Date(), fields: ["person": pair.0, "kind": "ask"], quote: pair.1, run: nil)
        }
    }
}
