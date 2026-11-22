import Foundation

/// Word error rate, the standard measure of a transcript against a reference: the fewest word substitutions,
/// deletions and insertions that turn the transcript into the reference, over the reference's word count. Case and
/// punctuation are ignored; an apostrophe inside a word is kept.
public struct WordErrorRate: Sendable, Equatable {
    public var errors: Int
    public var referenceWords: Int

    public var rate: Double { referenceWords == 0 ? (errors == 0 ? 0 : 1) : Double(errors) / Double(referenceWords) }

    public init(errors: Int, referenceWords: Int) {
        self.errors = errors
        self.referenceWords = referenceWords
    }

    public init(reference: String, transcript: String) {
        let truth = Self.words(reference)
        let heard = Self.words(transcript)
        var previous = Array(0...heard.count)
        for (i, word) in truth.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: heard.count)
            for (j, other) in heard.enumerated() {
                current[j + 1] = min(previous[j] + (word == other ? 0 : 1), previous[j + 1] + 1, current[j] + 1)
            }
            previous = current
        }
        self.init(errors: previous[heard.count], referenceWords: truth.count)
    }

    /// Several transcripts pooled: total errors over total reference words, as WER is reported across a test set.
    public static func pooled(_ parts: [WordErrorRate]) -> WordErrorRate {
        WordErrorRate(
            errors: parts.map(\.errors).reduce(0, +), referenceWords: parts.map(\.referenceWords).reduce(0, +))
    }

    static func words(_ text: String) -> [String] {
        text.lowercased().split { !($0.isLetter || $0.isNumber || $0 == "'") }.map(String.init)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'")) }.filter { !$0.isEmpty }
    }
}
