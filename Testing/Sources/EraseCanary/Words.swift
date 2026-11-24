import Foundation

/// The invented words of one scene. Each is a random 24-letter word that no real text holds, so a byte of it in a file
/// is a copy of the line it was written in.
struct Words {
    /// In the line the trigger erases.
    let canary = Words.random()
    /// In another line of the same chat.
    let sameChat = Words.random()
    /// In a line of another chat.
    let otherChat = Words.random()
    let mail = Words.random()
    let call = Words.random()
    let page = Words.random()
    let file = Words.random()
    let note = Words.random()

    static func random() -> String {
        String((0..<24).map { _ in "abcdefghijklmnopqrstuvwxyz".randomElement()! })
    }

    var all: [(name: String, word: String)] {
        [
            ("canary", canary), ("same chat", sameChat), ("other chat", otherChat), ("mail", mail), ("call", call),
            ("page", page), ("file", file), ("note", note),
        ]
    }
}
