import Foundation

public enum MeetingSubject: Sendable, Equatable {
    case person(String)
    case deal(String)
}

public struct DealIdentity: Sendable, Equatable {
    public var id: String
    public var names: [String]
    public var domains: [String]

    public init(id: String, names: [String], domains: [String]) {
        self.id = id
        self.names = names
        self.domains = domains
    }

    /// The deal's title and company names, and the domains written in its title and linked items.
    public init(_ deal: WorkObject) {
        let companies = deal.items.compactMap { $0.item.fields["company"] }
        let written = deal.items.compactMap { $0.item.fields["from"] } + companies + [deal.name]
        self.init(id: deal.id, names: [deal.name] + companies, domains: written.flatMap(MeetingMatch.domains(in:)))
    }
}

/// Links a meeting to people and deals by exact name, exact email domain or exact title. Plumbing, not judgment: a
/// match that two deals could claim is left unmatched, and nothing is matched by similar text.
public enum MeetingMatch {
    static let freeMail: Set<String> = [
        "gmail.com", "googlemail.com", "outlook.com", "hotmail.com", "live.com", "yahoo.com", "icloud.com", "me.com",
        "aol.com", "proton.me", "protonmail.com",
    ]

    /// Each person once, then each deal once. A guest matches a person by exact name. A guest's email domain, when it
    /// is not the owner's and not free mail, matches a deal that lists it, or whose name is the domain's company
    /// label (`acme` for `acme.com`). A meeting title that is exactly a deal's name matches that deal.
    public static func subjects(of meeting: Meeting, people: Set<String>, deals: [DealIdentity]) -> [MeetingSubject] {
        let known = Dictionary(people.map { (fold($0), $0) }, uniquingKeysWith: { first, _ in first })
        let own = Set(meeting.attendees.filter(\.isMe).compactMap { domain(of: $0.email) })
        let theirs = Set(meeting.guests.compactMap { domain(of: $0.email) }).subtracting(own).subtracting(freeMail)
        let byDomain = theirs.sorted().map { key in
            deals.filter { $0.domains.contains(key) || $0.names.contains { companyLabel(of: key) == fold($0) } }
        }
        let byTitle = deals.filter { $0.names.contains { fold($0) == fold(meeting.title) } }
        let found =
            meeting.guests.compactMap { known[fold($0.name)] }.map(MeetingSubject.person)
            + (byDomain + [byTitle]).compactMap { $0.count == 1 ? MeetingSubject.deal($0[0].id) : nil }
        return found.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    public static func domains(in text: String) -> [String] {
        text.split { $0.isWhitespace || "<>,;()\"'".contains($0) }.compactMap { word in
            let host = word.split(separator: "@", omittingEmptySubsequences: false).last ?? ""
            let trimmed = host.hasSuffix(".") ? String(host.dropLast()) : String(host)
            return isDomain(trimmed) ? trimmed.lowercased() : nil
        }
    }

    private static func domain(of email: String) -> String? {
        email.contains("@") ? fold(String(email.split(separator: "@").last ?? "")) : nil
    }

    /// `acme` for `acme.com`; nothing for `acme.co.uk`, where the company is not the second label.
    private static func companyLabel(of domain: String) -> String? {
        let labels = domain.split(separator: ".")
        return labels.count == 2 ? String(labels[0]) : nil
    }

    private static func isDomain(_ text: String) -> Bool {
        let labels = text.split(separator: ".", omittingEmptySubsequences: false)
        return labels.count >= 2 && labels.allSatisfy { !$0.isEmpty && !$0.hasPrefix("-") && !$0.hasSuffix("-") }
            && (labels.last.map { $0.count >= 2 && $0.allSatisfy(\.isLetter) } ?? false)
    }

    private static func fold(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }
}
