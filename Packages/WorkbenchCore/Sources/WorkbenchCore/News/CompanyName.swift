import Foundation

/// How company names and domains are compared: in code, with no fuzzy match. A name loses its case, accents and
/// marks, and nothing else: two names are one only when their words are the same, or one is an alias of the other.
public enum CompanyName {
    /// Names shorter than this never match by name; only a domain or a longer alias can name such a company.
    static let shortest = 3

    /// The words of a text: lower case, accents folded, "&" as "and", everything else that is not a letter or a digit
    /// a break.
    public static func words(_ text: String) -> [String] {
        text.nfc.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .split { !($0.isLetter || $0.isNumber) }.map(String.init)
    }

    /// The name as words.
    public static func normal(_ name: String) -> String { words(name).joined(separator: " ") }

    /// Every form a company's name may take in news: the name and each alias, each normalised. Forms shorter than
    /// `shortest` are left out.
    public static func terms(name: String, aliases: [String]) -> [String] {
        var seen: Set<String> = []
        return ([name] + aliases).map(normal).filter { $0.count >= shortest && seen.insert($0).inserted }
    }

    /// The words that may offer a company to the news reader: the name and each alias, and every run of their first
    /// words, so "Bolt Pay Private Limited" is offered by an article that says "Bolt Pay" or "Bolt". The offer is wide
    /// on purpose: the reader names which company the article is about, and code checks its answer. Runs shorter than
    /// `shortest` are left out.
    public static func offerTerms(name: String, aliases: [String]) -> [String] {
        var seen: Set<String> = []
        let runs = ([name] + aliases).flatMap { form -> [String] in
            let words = words(form)
            return words.indices.map { words[...$0].joined(separator: " ") }
        }
        return runs.filter { $0.count >= shortest && seen.insert($0).inserted }
    }

    /// A domain as typed: no scheme, no "www.", no path. Nil when what is left has no dot.
    public static func domain(_ typed: String) -> String? {
        var host = typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        host = host.replacing(#/^[a-z]+:\/\//#, with: "")
        host = String(host.prefix { $0 != "/" && $0 != "?" && $0 != "#" })
        host = host.replacing(#/^www\./#, with: "")
        return host.contains(".") && !host.contains(" ") ? host : nil
    }

    /// Whether `text` holds `term` as whole words.
    static func contains(_ text: [String], term: String) -> Bool {
        let wanted = term.split(separator: " ").map(String.init)
        guard !wanted.isEmpty, text.count >= wanted.count else { return false }
        return (0...(text.count - wanted.count)).contains { Array(text[$0..<($0 + wanted.count)]) == wanted }
    }

    /// Whether `text` names `domain`: as an address or a bare host, with or without "www." or a path.
    static func mentions(_ text: String, domain: String) -> Bool {
        let pieces = text.lowercased().split { !($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }
        return pieces.contains { piece in
            let host = piece.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return host == domain || host.hasSuffix("." + domain)
        }
    }
}
