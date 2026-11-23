import AppKit
import SwiftUI

/// The note of one project: plain writing, one paragraph for each block, saved a moment after the last key.
struct ProjectNotesView: View {
    static let placeholder = "Write what you know about this project."

    let project: String
    @Environment(ProjectNotes.self) private var notes

    var body: some View {
        if let editor = notes.editor(for: project) {
            NoteEditorBody(editor: editor)
        }
    }
}

private struct NoteEditorBody: View {
    let editor: NoteEditorModel
    @Environment(\.uiScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            NoteTextEditor(model: editor)
                .overlay(alignment: .topLeading) {
                    if editor.text.isEmpty {
                        Text(ProjectNotesView.placeholder)
                            .textStyle(.body)
                            .font(.system(size: 14 * scale))
                            .foregroundStyle(.supporting)
                            .allowsHitTesting(false)
                    }
                }
            if let problem = editor.problem { Text(problem).text(.caption) }
        }
        .keepsSaved(editor, reconcile: editor.reconcile)
    }
}
