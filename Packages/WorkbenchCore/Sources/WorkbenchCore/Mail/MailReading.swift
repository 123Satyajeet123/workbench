import Foundation

extension MailPart {
    /// Characters of mail text one reading sends at most (about 50k tokens), the same as for page text.
    public static let budget = WebPage.budget

    /// One numbered line a machine reads: the sender, the subject and the text; a deck page also names its file and
    /// page. Nil for a part not yet stored.
    public var evidence: Evidence? {
        guard let id else { return nil }
        let place = kind == .deck ? " — \(name) page \(page)" : ""
        return Evidence(
            id: id, start: seenAt, line: "\(sender) — \(subject)\(place): \(text)", quotable: [text])
    }

    /// The parts of a day a machine reads: only those of the named labels, a repeated text once, earliest first up to
    /// the budget. `leftOut` counts the parts past the budget.
    public static func reading(_ parts: [MailPart], labels: Set<String>, budget: Int = budget) -> (
        parts: [MailPart], leftOut: Int
    ) {
        var seen = Set<String>()
        var kept: [MailPart] = []
        var used = 0
        var leftOut = 0
        for part in parts.sorted(by: { ($0.id ?? 0) < ($1.id ?? 0) })
        where labels.contains(part.label) && seen.insert(part.threadID + "\n" + part.text).inserted {
            guard used + part.text.count <= budget else {
                leftOut += 1
                continue
            }
            used += part.text.count
            kept.append(part)
        }
        return (kept, leftOut)
    }
}
