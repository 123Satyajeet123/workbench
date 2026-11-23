import Foundation

/// What a text view edits: all of a note, or one run of its paragraphs. Offsets are in the text the view shows, in
/// UTF-16 units, so the view never learns where the run stands in the note.
protocol NoteRunEditing {
    var text: String { get }
    /// Counts the times the text must be drawn again from the model, not from the person's typing.
    var revision: Int { get }
    func edit(_ range: Range<Int>, with replacement: String)
    /// Moves the paragraph at `offset` by `distance` places and returns where it starts now.
    func moveBlock(atOffset offset: Int, by distance: Int) -> Int
    func setComposing(_ isComposing: Bool)
}
