import SwiftUI
import WorkbenchCore

/// What a fact is called on screen: the person and their own words. The machine's title stands in only for a fact that
/// has no quote.
struct FactHeadline: Equatable {
    let person: String
    let words: String
    let isQuote: Bool

    init(item: Item, title: String) {
        person = item["person"]
        let quote = item.quote.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        isQuote = !quote.isEmpty
        words = isQuote ? quote : title
    }

    /// The person in semibold, then the words; a quote stands in quotation marks.
    var text: Text {
        let shown = Text(verbatim: isQuote ? "“\(words)”" : words)
        guard !person.isEmpty else { return shown }
        return Text("\(Text(verbatim: person).fontWeight(.semibold))  \(shown)")
    }

    /// The headline as one plain string: what VoiceOver reads, and a reminder's title.
    var plain: String { [person, words].filter { !$0.isEmpty }.joined(separator: ": ") }
}
