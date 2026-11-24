import SwiftUI

/// A text that is edited where it stands. A click turns it into a field. Return or leaving the field saves, and Escape
/// keeps the old words. The caller sets the font.
struct InPlaceText: View {
    let text: String
    var prompt = ""
    @Binding var isEditing: Bool
    let commit: (String) -> Void
    @State private var draft = ""
    @State private var isHovered = false
    @FocusState private var hasFocus: Bool

    var body: some View {
        if isEditing {
            TextField(prompt, text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .focused($hasFocus)
                .onSubmit(finish)
                .onExitCommand { isEditing = false }
                .onChange(of: hasFocus) { _, focused in if !focused { finish() } }
                .onAppear {
                    draft = text
                    hasFocus = true
                }
                .overlay(alignment: .bottom) { Rectangle().fill(.tint).frame(height: 1).offset(y: 2) }
        } else {
            Text(text.isEmpty ? prompt : text)
                .foregroundStyle(text.isEmpty ? .supporting : .primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
                .onTapGesture { isEditing = true }
                .onHover { isHovered = $0 }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(.quaternary).frame(height: 1).offset(y: 2).opacity(isHovered ? 1 : 0)
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Edit")
        }
    }

    private func finish() {
        guard isEditing else { return }
        isEditing = false
        commit(draft)
    }
}
