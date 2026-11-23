import Foundation

extension MailPart {
    /// Characters of mail text one reading sends at most (about 50k tokens), the same as for page text.
    public static let budget = WebPage.budget

    /// One numbered line a machine reads, with the label and authority the store gave it: the sender, and for a deck
    /// page its file and page or for quoted text a note that it is quoted, then the text. Nil for a part with no stored line.
    public var evidence: Evidence? {
        guard let id else { return nil }
        let place = isDeck ? " — \(name) page \(page)" : isQuoted ? " (quoted)" : ""
        return Evidence(
            id: id, start: sentAt, line: "\(sender ?? "Unknown")\(place): \(text)", quotable: [text], lineID: lineID,
            provenance: provenance, consent: Consent(kind: .mail, label: label))
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
