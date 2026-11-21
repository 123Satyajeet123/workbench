import Foundation

enum FuzzySearch {
    static func filter<Item>(_ items: [Item], by query: String, name: (Item) -> String) -> [Item] {
        let query = words(query)
        guard !query.isEmpty else { return items }
        return items.enumerated()
            .compactMap { index, item in score(query, in: name(item)).map { (score: $0, index: index, item: item) } }
            .sorted { ($0.score, $0.index) < ($1.score, $1.index) }
            .map(\.item)
    }

    private static func score(_ query: [String], in name: String) -> Int? {
        let text = normalized(name)
        let phrase = query.joined(separator: " ")
        let textWords = words(name)
        if text.hasPrefix(phrase) { return 0 }
        if text.contains(phrase) { return 1 }
        if query.allSatisfy(text.contains) { return 2 }
        if query.allSatisfy({ word in textWords.contains { isOneEditAway(word, $0) } }) { return 3 }
        if query.allSatisfy({ isSubsequence($0, of: text) }) { return 4 }
        return nil
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func words(_ text: String) -> [String] {
        normalized(text).split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private static func isSubsequence(_ word: String, of text: String) -> Bool {
        var remaining = word[...]
        for character in text where character == remaining.first {
            remaining = remaining.dropFirst()
            if remaining.isEmpty { return true }
        }
        return remaining.isEmpty
    }

    private static func isOneEditAway(_ word: String, _ other: String) -> Bool {
        guard word.count >= 4, abs(word.count - other.count) <= 1 else { return false }
        let a = Array(word)
        let b = Array(other)
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count] <= 1
    }
}
