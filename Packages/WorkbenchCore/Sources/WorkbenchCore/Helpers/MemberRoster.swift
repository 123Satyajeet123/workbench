import Foundation

/// The members of one set, each known by one plain name. A stored value may hold an older label of a member (the
/// founder once showed as "Meera Rao (You)"). Every reader of a member field turns a value into a member through
/// `member(for:)`, so two spellings of one person never make two people.
public struct MemberRoster: Sendable, Equatable {
    /// The context entry that holds the plain name of the person who owns the Mac.
    public static let founderEntry = "founder"

    /// No member: every value stays as it is.
    public static let none = MemberRoster(names: [String]())

    private let memberByLabel: [String: String]

    /// `founder`, when given, is also known by the label that earlier versions wrote for the owner.
    public init(names: some Sequence<String>, founder: String? = nil) {
        var byLabel: [String: String] = [:]
        if let founder, !founder.isEmpty { byLabel[Self.olderLabel(ofFounder: founder)] = founder }
        for name in names where !name.isEmpty { byLabel[name] = name }
        memberByLabel = byLabel
    }

    /// The roster of a context set: its members, and the founder the context names.
    public init(set: String, in context: [String: [String]]) {
        self.init(names: context[set] ?? [], founder: context[Self.founderEntry]?.first)
    }

    /// The plain name of the member that `value` names, or nil when it names none.
    public func member(for value: String) -> String? { memberByLabel[value] }

    /// The member's plain name, or `value` itself when it names no member.
    public func canonical(_ value: String) -> String { member(for: value) ?? value }

    private static func olderLabel(ofFounder name: String) -> String { "\(name) (You)" }
}

extension HelperSpec {
    /// A fact of this machine as a page or board shows it: each member field holds the member's plain name, whichever
    /// label the stored value has. The copy is for reading; the stored row stays as it was written.
    public func resolvingMembers(of item: Item, in context: [String: [String]]) -> Item {
        guard item.task == task else { return item }
        var resolved = item
        for field in fields {
            guard case .member(let set) = field.kind else { continue }
            resolved.fields[field.name] = MemberRoster(set: set, in: context).canonical(item[field.name])
        }
        return resolved
    }
}
