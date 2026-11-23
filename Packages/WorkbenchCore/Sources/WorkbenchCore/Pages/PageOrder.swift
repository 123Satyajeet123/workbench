import Foundation

/// The order of a page when the person's paragraphs change. A note save knows only the paragraphs; the page also
/// holds machine blocks between them. Each machine block stays after the paragraph it followed.
enum PageOrder {
    /// `old` is the page's order before the save and `notes` the paragraphs after it. `isMachine` says which entries
    /// of `old` are machine blocks. `into` gives the paragraph an ended paragraph was joined to, or nil when it was
    /// deleted. A machine block whose paragraph was joined follows the paragraph that holds the words now; one whose
    /// paragraph was deleted follows the nearest earlier paragraph that lives, or leads the page when there is none.
    static func merged<Key: Hashable>(
        old: [Key], notes: [Key], isMachine: (Key) -> Bool, into: (Key) -> Key?
    ) -> [Key] {
        let living = Set(notes)
        var leading: [Key] = []
        var following: [Key: [Key]] = [:]
        for (index, block) in old.enumerated() where isMachine(block) {
            if let anchor = anchor(before: index, in: old, living: living, isMachine: isMachine, into: into) {
                following[anchor, default: []].append(block)
            } else {
                leading.append(block)
            }
        }
        return leading + notes.flatMap { [$0] + (following[$0] ?? []) }
    }

    /// The living paragraph the block at `index` follows: the paragraph before it, or where that one's words went,
    /// or the paragraph before that.
    private static func anchor<Key: Hashable>(
        before index: Int, in old: [Key], living: Set<Key>, isMachine: (Key) -> Bool, into: (Key) -> Key?
    ) -> Key? {
        for earlier in old[..<index].reversed() where !isMachine(earlier) {
            var paragraph = earlier
            var seen: Set<Key> = []
            while !living.contains(paragraph), seen.insert(paragraph).inserted, let next = into(paragraph) {
                paragraph = next
            }
            if living.contains(paragraph) { return paragraph }
        }
        return nil
    }
}
