import Foundation

/// Who the workspace is for, as data the prompts read: what the person is called in the work, their other trade, and
/// the languages they write in. A new workspace starts empty, so its prompts say "the person" and name no language.
public struct WorkspaceProfile: Codable, Equatable, Sendable {
    /// What the person is to their team, such as "founder". Empty: "person".
    public var role: String
    /// The trade the person's judgment comes from, such as "investor". Empty: "person".
    public var occupation: String
    /// The field the occupation works in, such as "venture" for an investor. Empty: none is named.
    public var specialty: String
    /// The languages the person's sources are written in, such as "Hindi". Empty: no language is named.
    public var languages: [String]

    public init(role: String = "", occupation: String = "", specialty: String = "", languages: [String] = []) {
        self.role = role
        self.occupation = occupation
        self.specialty = specialty
        self.languages = languages
    }

    /// The profile a store gets when it already holds prompts written for one founder-investor: those words, so the
    /// prompts and their hashes stay as they are.
    public static let continuity = WorkspaceProfile(
        role: "founder", occupation: "investor", specialty: "venture", languages: ["Hindi", "English", "Hinglish"])

    /// Fills the `{…}` words of a prompt text:
    /// `{the role}`, `{a role}`, `{the role's}`, `{a role's}`, `{The role}`, `{The role's}`, `{Role}`, `{the occupation}`, `{The occupation's}`, `{a trade}`, `{language note}`.
    /// The language note is empty, or starts with a space and ends with a full stop.
    public func render(_ template: String) -> String {
        template.replacing(#/\{[^{}]+\}/#) { match in
            words[String(match.output)] ?? String(match.output)
        }
    }

    private var words: [String: String] {
        let role = self.role.cleaned ?? "person"
        let occupation = self.occupation.cleaned ?? "person"
        return [
            "{the role}": "the " + role, "{a role}": Self.article(of: role) + " " + role,
            "{the role's}": "the \(role)'s", "{The role}": "The " + role, "{The role's}": "The \(role)'s",
            "{a role's}": "\(Self.article(of: role)) \(role)'s",
            "{Role}": role.prefix(1).uppercased() + role.dropFirst(), "{the occupation}": "the " + occupation,
            "{The occupation's}": "The \(occupation)'s", "{a trade}": trade,
            "{language note}": languageNote,
        ]
    }

    /// The specialty and the occupation with their article, such as "a venture investor".
    private var trade: String {
        let words = [specialty.cleaned, occupation.cleaned ?? "person"].compactMap(\.self)
        return Self.article(of: words[0]) + " " + words.joined(separator: " ")
    }

    private var languageNote: String {
        guard let last = languages.last else { return "" }
        let head = languages.dropLast().joined(separator: ", ")
        return " People write in " + (head.isEmpty ? last : head + " and " + last) + "."
    }

    private static func article(of word: String) -> String {
        word.first.map { "aeiouAEIOU".contains($0) } == true ? "an" : "a"
    }
}
