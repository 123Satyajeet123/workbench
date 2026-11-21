import Foundation

/// How company names and domains are compared: in code, with no fuzzy match. A name loses its case, accents, marks
/// and its legal form ("Pvt Ltd", "Private Limited"), so the legal name and the brand name can meet.
public enum CompanyName {
    /// Words that only say what legal form a company has. Dropped from the end of a name, however many.
    static let legalForms: Set<String> = [
        "pvt", "private", "limited", "ltd", "llp", "llc", "inc", "incorporated", "corp", "corporation", "co", "company",
        "opc", "plc",
    ]
    /// Words a legal name adds to a brand. A name also counts without them: "Bolt Technologies" for "Bolt".
    static let descriptors: Set<String> = [
        "technologies", "technology", "labs", "solutions", "services", "systems", "software", "india",
    ]
    /// Names shorter than this never match by name; only a domain or a longer alias can name such a company.
    static let shortest = 3

    /// The words of a text: lower case, accents folded, "&" as "and", everything else that is not a letter or a digit
    /// a break.
    public static func words(_ text: String) -> [String] {
        text.nfc.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .split { !($0.isLetter || $0.isNumber) }.map(String.init)
    }

    /// The name as words, without its legal form.
    public static func normal(_ name: String) -> String {
        var words = words(name)
        while words.count > 1, let last = words.last, legalForms.contains(last) { words.removeLast() }
        return words.joined(separator: " ")
    }

    /// Every form a company's name may take in news: the name, the name without its descriptors, and each alias, each
    /// normalised. Forms shorter than `shortest` are left out.
    public static func terms(name: String, aliases: [String]) -> [String] {
        var terms: [String] = []
        for form in [name] + aliases {
            let normal = normal(form)
            var words = normal.split(separator: " ").map(String.init)
            while words.count > 1, let last = words.last, descriptors.contains(last) { words.removeLast() }
            terms += [normal, words.joined(separator: " ")]
        }
        var seen: Set<String> = []
        return terms.filter { $0.count >= shortest && seen.insert($0).inserted }
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
