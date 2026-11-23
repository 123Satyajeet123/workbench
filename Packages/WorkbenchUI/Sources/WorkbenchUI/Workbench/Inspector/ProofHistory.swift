import Foundation
import WorkbenchCore

/// What the store knows about how a fact came to be and what the person did with it.
struct ProofHistory: Equatable {
    var machine: String?
    var version: Int?
    var found: Date?
    var marks: [DealStory.Marked] = []

    /// The history as short plain sentences, oldest first. Empty when nothing is known.
    func sentences(of item: Item, _ words: DateWords) -> [String] {
        [foundSentence(of: item, words), markSentence(words), dueSentence(of: item, words)].compactMap { $0 }
    }

    private func foundSentence(of item: Item, _ words: DateWords) -> String? {
        guard item.run != nil else { return nil }
        let who = (machine ?? "a machine you removed") + (version.map { " v\($0)" } ?? "")
        return "Found by \(who)" + (found.map { " on \(words.date($0))." } ?? ".")
    }

    private func markSentence(_ words: DateWords) -> String? {
        guard let latest = marks.last, let word = latest.state.answer else { return nil }
        return "You marked it \(word) on \(words.recent(latest.at))."
    }

    private func dueSentence(of item: Item, _ words: DateWords) -> String? {
        item.dueDay.map { "Due \(words.date($0.start))." }
    }
}

extension Mark {
    /// What the person answered; nil while the fact is unmarked.
    fileprivate var answer: String? {
        switch self {
        case .confirmed: "right"
        case .rejected: "wrong"
        case .proposed: nil
        }
    }
}
