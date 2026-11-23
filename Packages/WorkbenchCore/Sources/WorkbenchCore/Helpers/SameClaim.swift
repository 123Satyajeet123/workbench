import Foundation

/// Whether two items of a machine with no lifecycle say the same, so a mark or an earlier finding stands for the new
/// one. A machine with a lifecycle names the fact a new item restates (`Relation.sameAs`); code does not guess it.
enum SameClaim {
    /// A finding of facts repeats one that cites the same facts and has the same value in each of the spec's `choices`
    /// fields; a block of time repeats one it overlaps; a line item repeats one with the same line, fields and words.
    static func holds(_ new: Item, _ old: Item, citation: HelperSpec.Citation, choices: [String] = []) -> Bool {
        switch citation {
        case .range: new.start < old.end && old.start < new.end
        case .one: new.citeFirst == old.citeFirst && new.fields == old.fields && new.quote == old.quote
        case .facts:
            new[Item.factsField] == old[Item.factsField] && choices.allSatisfy { new[$0] == old[$0] }
        }
    }
}
