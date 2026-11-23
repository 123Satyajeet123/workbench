import Foundation
import Kernel
import Observation
import WorkbenchCore

/// The project notes of the app: one editor model for each project, kept while the app runs so a page that closes
/// loses no edit. The driver puts one in the environment.
@Observable
final class ProjectNotes {
    let store: Store
    private let owner: PersonID
    private var editors: [String: NoteEditorModel] = [:]

    init(store: Store, owner: PersonID) {
        self.store = store
        self.owner = owner
    }

    func editor(for project: String) -> NoteEditorModel? {
        if let known = editors[project] { return known }
        guard let note = NoteID(object: project) else { return nil }
        let editor = NoteEditorModel(note: note, store: store, owner: owner)
        editors[project] = editor
        return editor
    }
}
