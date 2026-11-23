import Foundation

/// What a reading does with the relations its proposals state.
extension HelperReader {
    /// A proposal repeats an earlier one of the reading when it names the same open fact. A machine with no lifecycle
    /// names none, and its blocks of time and findings repeat by what they say.
    func isRepeat(_ proposal: Verifier.Checked, among kept: [Verifier.Checked]) -> Bool {
        if let target = proposal.relation.target { return kept.contains { $0.relation.target == target } }
        return spec.lifecycle == nil && spec.citation != .one
            && kept.contains {
                SameClaim.holds(proposal.item, $0.item, citation: spec.citation, choices: spec.choiceFields)
            }
    }

    /// The facts the checked proposals open and the events they write. A `same_as` opens no fact: it restates the open
    /// one, and gives a new date when its date differs from the open fact's.
    static func apply(_ proposals: [Verifier.Checked], spec: HelperSpec, open: [Item]) -> ([Item], [Link]) {
        var items: [Item] = []
        var links: [Link] = []
        for proposal in proposals {
            let item = proposal.item
            let link = { (subject: Link.Subject, effect: Link.Effect) in
                Link(subject: subject, effect: effect, line: item.citeFirst, quote: item.quote, at: item.start)
            }
            switch proposal.relation {
            case .sameAs(let id):
                links.append(link(.stored(id), .restate))
                if let due = proposal.due, !due.isEmpty, due != dueNow(of: id, in: open, spec: spec) {
                    links.append(link(.stored(id), .dueChanged(due)))
                }
            case .new:
                items.append(item)
            case .unsure:
                items.append(item)
                links.append(link(.opened(items.count - 1), .flag))
            case .supersedes(let id):
                items.append(item)
                links.append(link(.stored(id), .supersede(by: items.count - 1)))
            case .closes(let id, let outcome):
                items.append(item)
                links.append(link(.stored(id), .closeProposed(outcome: outcome)))
            }
        }
        return (items, links)
    }

    /// The date an open fact is due now: the latest one a line gave, else the one it was opened with.
    private static func dueNow(of id: Int64, in open: [Item], spec: HelperSpec) -> String {
        guard let fact = open.first(where: { $0.id == id }) else { return "" }
        return fact.dueChanged ?? spec.lifecycle?.due.map { fact[$0] } ?? ""
    }
}
