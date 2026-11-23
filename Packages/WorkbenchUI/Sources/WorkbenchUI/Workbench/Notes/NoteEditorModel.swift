import Foundation
import Kernel
import Observation
import WorkbenchCore

/// One project note while the person writes it. Every edit goes into the document; a short pause after the last edit
/// saves what changed. Nothing is typed into a form: there is no Save.
@Observable
final class NoteEditorModel: NoteRunEditing {
    static let pause: Duration = .milliseconds(800)

    private(set) var document: NoteDocument
    /// Counts the times the text must be drawn again from the document, not from the person's typing.
    private(set) var revision = 0
    private(set) var problem: String?
    var isComposing = false
    /// Gives the order the person sees, for a page that holds more than this note's paragraphs. It gets the paragraphs
    /// to save, in order. A plain note has none.
    var pageOrder: (([BlockID]) -> [PageBlockRef])?

    private let store: Store
    private let owner: PersonID
    private let pause: Duration
    private var pendingSave: Task<Void, Never>?
    private var saving: Task<Void, Never>?

    init(note: NoteID, store: Store, owner: PersonID, pause: Duration = NoteEditorModel.pause) {
        self.store = store
        self.owner = owner
        self.pause = pause
        document = NoteDocument(note: note, stored: (try? store.queries.noteBlocks(of: note)) ?? [])
    }

    var text: String { document.text }

    func edit(_ range: Range<Int>, with replacement: String) {
        document.replace(range, with: replacement)
        scheduleSave()
    }

    /// Moves the paragraph at `offset` and returns where it starts now.
    func moveBlock(atOffset offset: Int, by distance: Int) -> Int {
        let block = document.blockID(at: offset)
        document.move(block, by: distance)
        revision += 1
        scheduleSave()
        return document.offset(of: block)
    }

    func setComposing(_ isComposing: Bool) { self.isComposing = isComposing }

    /// Draws the note again from the store when the person deleted it, or changed it, in another place. What the
    /// person wrote since the last save stays.
    func reconcile() {
        guard let stored = try? store.queries.noteBlocks(of: document.note) else { return }
        let before = document.text
        document.drop(document.savedBlocks.subtracting(stored.map(\.id)))
        if document.text != before { revision += 1 }
    }

    /// Saves now and waits: the page closes, or the app goes to the back.
    func flush() async {
        pendingSave?.cancel()
        await persist()
    }

    /// Saves before the app quits. The app does not wait for a task, so this waits for the write itself.
    func saveBeforeQuit() {
        guard let change = pendingChange() else { return }
        let (store, owner) = (store, owner)
        let finished = DispatchSemaphore(value: 0)
        Task.detached {
            _ = try? await store.saveNote(change, owner: owner)
            finished.signal()
        }
        _ = finished.wait(timeout: .now() + 2)
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [pause] in
            try? await Task.sleep(for: pause)
            guard !Task.isCancelled else { return }
            await persist()
        }
    }

    /// Saves what is pending. A call while a save runs waits for it, then saves what changed meanwhile.
    private func persist() async {
        while let running = saving { await running.value }
        let task = Task {
            await drain()
            saving = nil
        }
        saving = task
        await task.value
    }

    private func drain() async {
        while !isComposing, let change = pendingChange() {
            do {
                try await save(change)
                problem = nil
            } catch {
                problem = "Could not save this note. Your words are still here. Workbench will try again."
                scheduleSave()
                return
            }
        }
    }

    private func pendingChange() -> NoteChange? {
        guard var change = document.pendingChange() else { return nil }
        change.pageOrder = pageOrder?(change.order)
        return change
    }

    private func save(_ change: NoteChange) async throws {
        let report = try await store.saveNote(change, owner: owner)
        document.didSave(change)
        guard report.refusedAfterRevoke > 0 else { return }
        let held = Set(try store.queries.noteBlocks(of: document.note).map(\.id))
        document.rename(Set(change.blocks.map(\.id)).subtracting(held))
    }
}
