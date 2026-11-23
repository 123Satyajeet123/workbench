import Foundation
import Kernel

/// How far the words of a line may be trusted, from the least to the most. A fact is never more trusted than the
/// least trusted line it rests on.
public enum Authority: String, CaseIterable, Comparable, Sendable {
    case unknown
    case forwardedOrQuoted = "forwarded_or_quoted"
    case groupMember = "group_member"
    case ownWords = "own_words"

    public static func < (lhs: Self, rhs: Self) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }

    /// The authority of a line from the sender the source recorded. The owner's own lines are their own words and
    /// any other sender is another person; a line with no sender is unknown. No reader keeps a forwarded flag yet, so
    /// no stored line is `forwardedOrQuoted`: the level is in the order, ready for a reader that keeps the flag.
    public init(actor: String?, owner: String) {
        self = actor.map { $0 == owner ? .ownWords : .groupMember } ?? .unknown
    }
}

/// What a source knows about where a line came from, set when the line was stored and never by a model.
public struct Provenance: Sendable, Equatable {
    public var label: Label
    public var authority: Authority

    public init(label: Label, authority: Authority) {
        self.label = label
        self.authority = authority
    }
}

/// Who may read a fact and how far it may be trusted, computed by code from what the fact rests on. The model read the
/// whole window, so its words can carry any line of it: the label is the join of the labels of the cited lines, the
/// cited facts and every line of the window, and it is nil when one of them has no known label, and then no reader is
/// known. The authority is the least of the authorities of the same lines and facts; a line with no known provenance
/// is `unknown`.
public struct Standing: Sendable, Equatable {
    public var label: Label?
    public var authority: Authority

    public init(label: Label?, authority: Authority) {
        self.label = label
        self.authority = authority
    }

    /// The standing of a fact that cites `lines` and `facts`, read inside `window`.
    public init(citing lines: [Evidence], facts: [Item], window: [Evidence]) {
        self = Self.merged((lines + window).map(\.standing) + facts.map(\.standing))
    }

    /// The standing of anything made from all of `parts`: every label joined, the least authority.
    static func merged(_ parts: [Standing]) -> Standing {
        let known = parts.compactMap(\.label)
        let joined = known.count == parts.count ? known.first.map { $0.joined(with: known.dropFirst()) } : nil
        return Standing(label: joined, authority: parts.map(\.authority).min() ?? .unknown)
    }
}

extension Evidence {
    /// What this line is worth as a ground: its stored label and authority, or nothing known.
    var standing: Standing {
        Standing(label: provenance?.label, authority: provenance?.authority ?? .unknown)
    }
}

extension Item {
    var standing: Standing { Standing(label: label, authority: authority) }
}
