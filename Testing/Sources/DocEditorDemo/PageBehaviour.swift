import AppKit
import EditorHarness
import Foundation
import GRDB
import Kernel

@testable import PageSnapshot
@testable import WorkbenchCore
@testable import WorkbenchUI

/// The page of a machine in the model the app uses: proposals, marks, and a store the old editor wrote.
extension Behaviour {
    /// The machine page model with its editor in a window that is never shown, on blocks of every kind.
    @MainActor
    private static func openPage() async throws -> (desk: PageDesk, editor: OffscreenEditor) {
        let desk = try await PageDesk()
        desk.page.refresh()
        try desk.proposeTheFullPage()
        await desk.page.accept()
        desk.page.openEditor(appearance: .light, reduceMotion: false, scale: 1)
        guard let host = desk.page.editor?.host else { throw DemoFailure("the page did not open its editor") }
        let editor = OffscreenEditor(host: host, dark: false)
        guard
            try await editor.waitUntil(
                "return window.wbEditor && document.querySelectorAll('.machine').length >= 5")
        else { throw DemoFailure("the editor did not show the page") }
        return (desk, editor)
    }

    private static func standings(_ editor: OffscreenEditor) async throws -> String {
        try await editor.json(
            "return [...document.querySelectorAll('.machine')].map(n => n.dataset.standing + (n.querySelector('.standing') ? ':' + n.querySelector('.standing').textContent : ''))"
        )
    }

    private static func offeredNow(_ native: MachineActing, _ ids: [Int64], _ desk: PageDesk) throws -> [[FactAction]] {
        try ids.map { id in
            let item = try (desk.helper.items + desk.helper.open + desk.helper.closed).first { $0.id == id }
                .orFail("fact \(id)")
            return native.offered(for: item)
        }
    }

    private static func storedBlocks(_ desk: PageDesk) throws -> Set<String> {
        Set(
            try desk.store.queries.page(of: desk.machine.page!, for: PageViewer(owner: desk.owner)).page.blocks.keys
                .map(\.rawValue))
    }

    /// A proposal shows on the page as new, replacing and removed blocks, and is stored only when accepted.
    static func proposal() async throws -> String {
        let (desk, editor) = try await openPage()
        defer { desk.close() }
        let live = try storedBlocks(desk)
        try desk.proposeAChange()
        guard try await editor.waitUntil("return document.querySelector('.machine[data-standing=\"added\"]') !== null")
        else { throw DemoFailure("the proposal did not show") }
        let shown = try await standings(editor)
        for word in ["added:New", "replacement:Replaces a block", "removed:Will be removed"] {
            guard shown.contains(word) else { throw DemoFailure("missing \(word) in \(shown)") }
        }
        guard try storedBlocks(desk) == live else { throw DemoFailure("the proposal changed the store") }
        let paragraph = desk.paragraphs[0].rawValue
        try await editor.run(
            "window.wbEditor.setTextCursorPosition('\(paragraph)', 'end'); window.wbEditor.focus();")
        editor.insertText(" typed during the proposal")
        guard await desk.page.editor?.flush() == true else { throw DemoFailure("the editor did not settle") }
        let order = try desk.store.queries.page(of: desk.machine.page!, for: PageViewer(owner: desk.owner)).page.order
        let machines = order.compactMap { if case .machine(let id) = $0 { id.rawValue } else { nil } }
        guard Set(machines) == live else {
            throw DemoFailure("typing stored a proposed block in the order: \(machines)")
        }
        desk.page.discard()
        guard
            try await editor.waitUntil(
                "return document.querySelector('.machine[data-standing]:not([data-standing=\"live\"])') === null")
        else { throw DemoFailure("discard left proposed blocks: \(try await standings(editor))") }
        let afterDiscard = try await editor.json("return document.querySelectorAll('.machine').length")
        guard try storedBlocks(desk) == live, afterDiscard == "\(live.count)" else {
            throw DemoFailure("discard: \(afterDiscard) blocks, store \(try storedBlocks(desk).count)")
        }
        try desk.proposeAChange()
        await desk.page.accept()
        guard
            try await editor.waitUntil(
                "return document.querySelector('.machine[data-standing]:not([data-standing=\"live\"])') === null")
        else { throw DemoFailure("accept left proposed blocks: \(try await standings(editor))") }
        let accepted = try storedBlocks(desk)
        guard accepted != live,
            try await editor.json("return document.body.textContent.includes('Cassandra waits for the plan')") == "true"
        else { throw DemoFailure("accept did not store the change") }
        return
            "pending: \(shown) (store unchanged, typing stored no proposed block); discard: \(afterDiscard) live blocks, store unchanged; accept: all live, store holds \(accepted.count) blocks (was \(live.count)) and the new line shows"
    }

    /// A mark made in the editor is the mark the fact card makes: same state, same store.
    static func marksParity() async throws -> String {
        let (desk, editor) = try await openPage()
        defer { desk.close() }
        guard let first = desk.facts[0].id, let second = desk.facts[1].id else { throw DemoFailure("no facts") }
        _ = try await editor.waitUntil("return document.querySelectorAll('.fact .mark-done').length >= 2")
        let offered = try await editor.json(
            "return [...document.querySelectorAll('.fact')].slice(0, 2).map(n => [...n.querySelectorAll('.mark')].map(b => b.textContent))"
        )
        guard offered.contains("Done") else { throw DemoFailure("no Done mark is offered: \(offered)") }
        try await editor.run("document.querySelectorAll('.fact')[0].querySelector('.mark-done').click()")
        guard await desk.page.editor?.flush() == true else { throw DemoFailure("the editor did not settle") }
        let helper = desk.helper
        let native = MachineActing(helper: helper)
        let item = try desk.facts.first { $0.id == second }.orFail("the second fact")
        let before = try offeredNow(native, [first, second], desk)
        _ = try native.perform(.done, on: [item], surface: .machinePage)
        let after = try offeredNow(native, [first, second], desk)
        guard before[1].contains(.done), !before[0].contains(.done), after[0] == after[1], !after[1].contains(.done)
        else {
            throw DemoFailure("offered before \(before), after \(after)")
        }
        let states = after.map { "\($0.map(\.title))" }
        return
            "marks offered per row: \(offered); editor Done on fact \(first) and the card's Done on fact \(second) both lose Done and are closed the same way; actions offered now: \(states.joined(separator: " / "))"
    }
}

extension Optional {
    fileprivate func orFail(_ message: String) throws -> Wrapped {
        guard let self else { throw DemoFailure(message) }
        return self
    }
}
