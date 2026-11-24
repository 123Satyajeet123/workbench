import AppKit
import Foundation
import Kernel

@testable import WorkbenchCore
@testable import WorkbenchUI

/// One page in a scratch store with its editor in a window that is never shown.
@MainActor
public struct Session {
    public let desk: Desk
    public let editor: OffscreenEditor
    public let controller: PageEditorController

    public static let machineReady =
        "return window.wbEditor && window.wbEditor.document.length > 1 && document.querySelector('.machine') !== null"

    /// A page of machine blocks only, with no paragraph of the person's, is ready when its first block is drawn.
    public static let blocksReady =
        "return window.wbEditor && window.wbEditor.document.length > 0 && document.querySelector('.machine') !== null"

    public init(
        desk: Desk, dark: Bool = false, width: CGFloat = 900, facts: [Item] = [], summaries: [String: Summary] = [:],
        ready: String = Session.machineReady
    ) async throws {
        self.desk = desk
        editor = OffscreenEditor(size: CGSize(width: width, height: 1300), dark: dark)
        controller = try PageEditorController(
            store: desk.store, page: desk.page, owner: desk.owner, host: editor.host,
            appearance: dark ? .dark : .light, reduceMotion: false,
            views: {
                MachineViewBuilder(
                    facts: facts, titleOf: { item in desk.machine.map { item[$0.spec.title] } ?? "" },
                    lens: FactsLens(spec: desk.machine?.spec ?? .followUps, now: Date()), summaries: summaries,
                    pickerNote: { _ in nil })
            })
        controller.start()
        guard try await editor.waitUntil(ready) else {
            throw DemoFailure("the editor did not load the page (\(controller.problem ?? "no problem reported"))")
        }
    }

    /// The page as the editor shows it: type, id and words of each block.
    public func shown() async throws -> [String] {
        let text = try await editor.json(
            "return window.wbEditor.document.map(b => b.type + '|' + b.id + '|' + (b.content||[]).map(c=>c.text||'').join(''))"
        )
        return try JSONDecoder().decode([String].self, from: Data(text.utf8))
    }

    /// The blocks with words, and the machine blocks: the editor also holds an empty paragraph to write in.
    public func filled() async throws -> [String] {
        try await shown().filter { !($0.hasPrefix("paragraph") && $0.hasSuffix("|")) }
    }

    public func storedWords() throws -> [String] { try desk.store.queries.noteBlocks(of: desk.note).map(\.text) }

    public func place(_ id: BlockID, at end: String = "end") async throws {
        try await editor.run(
            "window.wbEditor.setTextCursorPosition('\(id.rawValue)', '\(end)'); window.wbEditor.focus();")
    }

    public func settle() async throws {
        try await Task.sleep(for: .milliseconds(250))
        guard await controller.flush() else { throw DemoFailure("the editor did not settle") }
    }
}
