import Foundation

/// Who may receive what a machine read: the disclosure rule from YC's qm (MIT, `src/memory/disclosure.ts`), ported.
/// A share goes to the team only when every recipient can already read its source. An unknown audience refuses all.
public enum Audience {
    /// The recipients who cannot read the source. `readers` is nil when the source's audience is unknown.
    public static func missing(recipients: [Team.Person], readers: Set<Int64>?) -> [Team.Person] {
        guard let readers else { return recipients }
        return recipients.filter { $0.id.map(readers.contains) != true }
    }

    /// Teammates who can read a WhatsApp group: linked to a WhatsApp id that is a member of the group now.
    public static func readers(links: [Int64: String], group: Set<String>) -> Set<Int64> {
        Set(links.filter { group.contains($0.value) }.keys)
    }
}

/// One machine's items of one day, shared with the people who could already read their source. It carries each item's
/// fields, quote and its author's mark; never the source's other lines.
public struct SharedDay: TeamFile, Equatable, Identifiable {
    public struct Entry: Codable, Sendable, Equatable {
        public var fields: [String: String]
        public var quote: String
        public var start: Date
        public var end: Date
        /// The author's mark: confirmed, or proposed (not yet reviewed). Rejected items are never shared.
        public var state: Mark
    }

    public static let subfolder = "days"

    public var author: String
    public var machine: String
    public var task: String
    public var day: String
    /// Field names in the order the machine's spec lists them.
    public var columns: [String]
    /// Everyone the author shared with, by name, the author first.
    public var audience: [String]
    public var sharedAt: Date
    public var entries: [Entry]

    public init(
        author: String, machine: Machine, day: WorkDay, items: [Item], audience: [String], at date: Date
    ) {
        self.author = author
        self.machine = machine.name
        task = machine.task
        self.day = day.description
        columns = machine.spec.fields.map(\.name)
        self.audience = audience
        sharedAt = date
        entries = items.filter { $0.state != .rejected }.map {
            Entry(fields: $0.fields, quote: $0.quote, start: $0.start, end: $0.end, state: $0.state)
        }
    }

    public var id: String { ([author] + fileParts).joined(separator: "/") }
    public var fileParts: [String] { [task, day] }

    /// The receiving Mac checks again: a day shows only to a person in its audience.
    public func isVisible(to person: String) -> Bool { audience.contains(person) }
}

/// An act that left the founder's store, as logged.
public struct Action: Sendable, Equatable {
    public var at: Date
    public var kind: String
    public var target: String
    public var detail: [String: String]
}

extension Store {
    /// The founder says who a teammate is in WhatsApp. The latest link wins.
    public func link(_ person: Team.Person, whatsapp jid: String) throws {
        guard let id = person.id, let jid = jid.cleaned else { return }
        try database.run(
            "INSERT INTO member_handle(member_id, kind, handle, at) VALUES (?, 'whatsapp', ?, ?)",
            [.int(id), .text(jid), SQLValue(clock())])
    }

    public func log(_ kind: String, target: String, detail: [String: String] = [:]) throws {
        try database.run(
            "INSERT INTO action(at, kind, target, detail) VALUES (?,?,?,?)",
            [SQLValue(clock()), .text(kind), .text(target), .text(try Coding.json(detail))])
    }
}

extension Queries {
    /// Each teammate's latest WhatsApp id, by member id.
    public func whatsappLinks() throws -> [Int64: String] {
        let rows = try database.rows(
            """
            SELECT member_id, handle FROM member_handle WHERE id IN
                (SELECT MAX(id) FROM member_handle WHERE kind = 'whatsapp' GROUP BY member_id)
            """)
        return Dictionary(
            rows.compactMap { row in row[0].integer.flatMap { id in row[1].string.map { (id, $0) } } },
            uniquingKeysWith: { a, _ in a })
    }

    /// Every logged act, oldest first.
    public func actions() throws -> [Action] {
        try database.rows("SELECT at, kind, target, detail FROM action ORDER BY id").map {
            Action(
                at: $0[0].date ?? .distantPast, kind: $0[1].string ?? "", target: $0[2].string ?? "",
                detail: (try? Coding.value([String: String].self, from: $0[3].string ?? "{}")) ?? [:])
        }
    }
}
