import AppKit
import Foundation
import Kernel
import SQLite3
import SwiftUI
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// The note editor through the real text view: what a person types, deletes, pastes and undoes reaches the store as the
/// right lines, and the document and the text on screen never part.
@MainActor
@Suite struct NoteEditorTests {
    static let owner = try! PersonID("owner-1")
    static let note = NoteID(object: "Bolt Pay")!

    struct Editor {
        let store: Store
        let model: NoteEditorModel
        let view: NoteTextView
        let window: NSWindow

        init(store: Store? = nil, pause: Duration = .milliseconds(40), width: CGFloat = 520) throws {
            let store = try store ?? scratchStore()
            self.store = store
            model = NoteEditorModel(
                note: NoteEditorTests.note, store: store, owner: NoteEditorTests.owner, pause: pause)
            let host = NSHostingView(rootView: NoteTextEditor(model: model).frame(width: width))
            window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: width, height: 400), styleMask: [], backing: .buffered,
                defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            view = try #require(Self.textView(in: host))
            window.makeFirstResponder(view)
        }

        static func textView(in view: NSView) -> NoteTextView? {
            if let found = view as? NoteTextView { return found }
            return view.subviews.lazy.compactMap { textView(in: $0) }.first
        }

        func type(_ text: String) { view.insertText(text, replacementRange: view.selectedRange()) }
        func returnKey() { view.insertNewline(nil) }
        func backspace() { view.deleteBackward(nil) }
        func caret(_ offset: Int) { view.setSelectedRange(NSRange(location: offset, length: 0)) }
        func select(_ range: Range<Int>) {
            view.setSelectedRange(NSRange(location: range.lowerBound, length: range.count))
        }
        var inSync: Bool { view.string == model.text }
        var stored: [String] { (try? store.queries.noteBlocks(of: NoteEditorTests.note).map(\.text)) ?? [] }
    }

    static func run(_ sql: String, in store: Store) {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        sqlite3_open(store.directory.appending(path: "workbench.sqlite").path, &db)
        sqlite3_busy_timeout(db, 5000)
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    static func column(_ sql: String, in store: Store) -> [String] {
        var db: OpaquePointer?
        var statement: OpaquePointer?
        defer {
            sqlite3_finalize(statement)
            sqlite3_close(db)
        }
        sqlite3_open_v2(store.directory.appending(path: "workbench.sqlite").path, &db, SQLITE_OPEN_READONLY, nil)
        sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        var values: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            values.append(String(cString: sqlite3_column_text(statement, 0)))
        }
        return values
    }

    static func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
        return condition()
    }

    @Test func typingAndReturnMakeParagraphsThatAreSavedAfterAPause() async throws {
        let editor = try Editor()
        editor.type("Send the deck")
        editor.returnKey()
        editor.type("Call Meera")
        #expect(editor.inSync && editor.stored.isEmpty, "nothing is saved before the pause")
        #expect(await Self.eventually { editor.stored == ["Send the deck", "Call Meera"] })
    }

    @Test func backspaceAtTheStartOfAParagraphJoinsItToTheOneBeforeAndKeepsItsWordsInTheStore() async throws {
        let editor = try Editor()
        editor.type("One")
        editor.returnKey()
        editor.type("Two")
        await editor.model.flush()
        editor.caret(4)
        editor.backspace()
        #expect(editor.inSync && editor.model.text == "OneTwo")
        await editor.model.flush()
        #expect(editor.stored == ["OneTwo"])
        let lines = Self.column("SELECT text FROM evidence WHERE tombstone = 0 ORDER BY id", in: editor.store)
        #expect(lines.contains("Two"), "the joined paragraph's line stays as it was")
    }

    @Test func aDeletedParagraphIsGoneFromTheStoreAndAnUndoWritesItBackAsNewWords() async throws {
        let editor = try Editor()
        editor.type("Keep")
        editor.returnKey()
        editor.type("Remove me")
        await editor.model.flush()
        editor.select(5..<14)
        editor.backspace()
        await editor.model.flush()
        #expect(editor.inSync && editor.stored == ["Keep"])
        editor.view.undoManager?.undo()
        #expect(editor.inSync, "the document follows the undo")
        await editor.model.flush()
        #expect(editor.stored == ["Keep", "Remove me"])
    }

    @Test func aPasteOfSeveralLinesMakesOneParagraphForEachWhateverTheLineBreak() async throws {
        let editor = try Editor()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("A\r\nB\rC\u{2028}D", forType: .string)
        editor.view.paste(nil)
        #expect(editor.inSync && editor.model.text == "A\nB\nC\nD")
        await editor.model.flush()
        #expect(editor.stored == ["A", "B", "C", "D"])
    }

    @Test func aParagraphMovesUpWithItsNameAndTheOrderIsSaved() async throws {
        let editor = try Editor()
        editor.type("One")
        editor.returnKey()
        editor.type("Two")
        await editor.model.flush()
        let before = editor.model.document.blocks.map(\.id)
        editor.view.moveBlock?(-1)
        #expect(editor.inSync && editor.model.text == "Two\nOne")
        #expect(editor.model.document.blocks.map(\.id) == before.reversed())
        await editor.model.flush()
        #expect(editor.stored == ["Two", "One"])
    }

    @Test func devanagariAndEmojiTypedAndSplitSurviveTheStore() async throws {
        let editor = try Editor()
        editor.type("नमस्ते 👍 दुनिया")
        editor.caret("नमस्ते 👍".utf16.count)
        editor.returnKey()
        await editor.model.flush()
        #expect(editor.inSync && editor.stored == ["नमस्ते 👍", " दुनिया"])
    }

    @Test func typingWhileASaveRunsLosesNothing() async throws {
        let editor = try Editor(pause: .milliseconds(1))
        for index in 0..<60 {
            editor.type("w\(index) ")
            if index % 7 == 0 { editor.returnKey() }
            try? await Task.sleep(for: .milliseconds(2))
        }
        await editor.model.flush()
        #expect(editor.inSync && editor.stored.joined(separator: "\n") == editor.model.text)
        #expect(!editor.model.document.hasUnsavedChanges)
    }

    @Test func theAppQuittingSavesWhatIsPending() throws {
        let editor = try Editor(pause: .seconds(60))
        editor.type("Written just before quit")
        #expect(editor.stored.isEmpty)
        editor.model.saveBeforeQuit()
        #expect(editor.stored == ["Written just before quit"])
    }

    @Test func aNoteDeletedWhileItsPageIsOpenLeavesTheEditorAfterAReconcile() async throws {
        let editor = try Editor()
        editor.type("Secret plan")
        await editor.model.flush()
        _ = try await editor.store.deleteNote(Self.note, owner: Self.owner)
        editor.model.reconcile()
        #expect(editor.model.text.isEmpty && !editor.model.document.hasUnsavedChanges)
        #expect(editor.stored.isEmpty)
    }

    @Test func wordsTypedAfterTheNoteWasDeletedElsewhereAreSavedUnderNewNamesAndTheOldOnesStayGone() async throws {
        let editor = try Editor()
        editor.type("Old")
        await editor.model.flush()
        _ = try await editor.store.deleteNote(Self.note, owner: Self.owner)
        editor.type(" and new")
        await editor.model.flush()
        #expect(editor.stored == ["Old and new"], "the person kept typing in a paragraph that is still on screen")
        #expect(!editor.model.document.hasUnsavedChanges)
    }

    @Test func aSaveThatFailsKeepsTheWordsShowsAPlainProblemAndTriesAgain() async throws {
        let store = try scratchStore()
        let editor = try Editor(store: store)
        Self.run(
            "CREATE TRIGGER no_rows BEFORE INSERT ON container_order BEGIN SELECT RAISE(ABORT, 'no'); END", in: store)
        editor.type("Kept")
        #expect(await Self.eventually { editor.model.problem != nil })
        #expect(editor.model.text == "Kept")
        Self.run("DROP TRIGGER no_rows", in: store)
        #expect(await Self.eventually { editor.stored == ["Kept"] && editor.model.problem == nil })
    }

    @Test func aNoteOfAThousandParagraphsOpensAndTakesAnEditQuickly() async throws {
        let store = try scratchStore()
        var document = NoteDocument(note: Self.note)
        document.replace(0..<0, with: (0..<1000).map { "Paragraph \($0)" }.joined(separator: "\n"))
        _ = try await store.saveNote(try #require(document.pendingChange()), owner: Self.owner)
        let clock = ContinuousClock()
        var editor: Editor?
        let opened = try clock.measure { editor = try Editor(store: store) }
        let open = try #require(editor)
        #expect(open.inSync && open.model.document.blocks.count == 1000)
        let typed = clock.measure { for _ in 0..<20 { open.type("x") } }
        #expect(opened < .seconds(3) && typed < .seconds(1), "open \(opened), 20 keys \(typed)")
    }

    @Test func theTextIsAtTheSizeOfTheZoom() throws {
        #expect(NoteTextEditor.Coordinator.attributes(scale: 1.5)[.font] as? NSFont == .systemFont(ofSize: 21))
    }
}
