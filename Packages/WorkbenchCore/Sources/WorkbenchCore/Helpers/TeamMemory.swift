import Foundation
import GRDB

public enum Audience {
    public static func missing(recipients: [Team.Person], readers: Set<Int64>?) -> [Team.Person] {
        guard let readers else { return recipients }
        return recipients.filter { $0.id.map(readers.contains) != true }
    }

    public static func readers(links: [Int64: String], group: Set<String>) -> Set<Int64> {
        Set(links.filter { group.contains($0.value) }.keys)
    }
}

public struct SharedDay: TeamFile, Equatable, Identifiable {
    public struct Entry: Codable, Sendable, Equatable {
        public var fields: [String: String]
        public var quote: String
        public var start: Date
        public var end: Date
        public var state: Mark
    }

    public static let subfolder = "days"

    public var author: String
    public var machine: String
    public var task: String
    public var day: String
    public var columns: [String]
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
    public var owner: String { author }
    public var fileParts: [String] { [task, day] }

    public func isVisible(to person: String) -> Bool { audience.contains(person) }
}

public struct Action: Sendable, Equatable {
    public var at: Date
    public var kind: String
    public var target: String
    public var detail: [String: String]
}

extension Store {
    public func link(_ person: Team.Person, whatsapp jid: String) throws {
        guard let id = person.id, let jid = jid.cleaned else { return }
        try writer.write { db in
            try db.execute(
                sql: "INSERT INTO member_handle(member_id, kind, handle, at) VALUES (?, 'whatsapp', ?, ?)",
                arguments: [id, jid, clock().stored])
        }
    }

    public func addTeammate(_ name: String, whatsapp jid: String) throws {
        guard let name = name.cleaned, let jid = jid.cleaned else { return }
        try writer.write { db in
            guard try Self.teammate(db, whatsapp: jid) == nil else { return }
            let now = clock().stored
            let team: Int64
            if let existing = try Int64.fetchOne(db, sql: "SELECT id FROM team LIMIT 1") {
                team = existing
            } else {
                try db.execute(sql: "INSERT INTO team(name, created_at) VALUES ('Your team', ?)", arguments: [now])
                team = db.lastInsertedRowID
            }
            try db.execute(
                sql: "INSERT INTO member(team_id, name, role, is_me, added_at) VALUES (?, ?, '', 0, ?)",
                arguments: [team, name, now])
            try db.execute(
                sql: "INSERT INTO member_handle(member_id, kind, handle, at) VALUES (?, 'whatsapp', ?, ?)",
                arguments: [db.lastInsertedRowID, jid, now])
        }
    }

    public func removeTeammate(whatsapp jid: String) throws {
        try writer.write { db in
            guard let member = try Self.teammate(db, whatsapp: jid) else { return }
            try db.execute(
                sql: "UPDATE member SET removed_at = ? WHERE id = ?", arguments: [clock().stored, member])
        }
    }

    private static func teammate(_ db: Database, whatsapp jid: String) throws -> Int64? {
        try Int64.fetchOne(
            db,
            sql: """
                SELECT member.id FROM member JOIN member_handle ON member_handle.member_id = member.id
                WHERE member.removed_at IS NULL AND member_handle.kind = 'whatsapp' AND member_handle.handle = ?
                """,
            arguments: [jid])
    }

    public func log(_ kind: String, target: String, detail: [String: String] = [:]) throws {
        let json = try Coding.json(detail)
        try writer.write { db in
            try db.execute(
                sql: "INSERT INTO action(at, kind, target, detail) VALUES (?,?,?,?)",
                arguments: [clock().stored, kind, target, json])
        }
    }
}

extension Queries {
    public func whatsappLinks() throws -> [Int64: String] {
        let links = try reader.read { db in
            try db.fetch(
                "member_handle",
                """
                SELECT member_id, handle FROM member_handle WHERE id IN
                    (SELECT MAX(id) FROM member_handle WHERE kind = 'whatsapp' GROUP BY member_id)
                """
            ) { row in (member: try row.value(0) as Int64, handle: try row.value(1) as String) }
        }
        return Dictionary(links.map { ($0.member, $0.handle) }, uniquingKeysWith: { a, _ in a })
    }

    public func actions() throws -> [Action] {
        try reader.read { db in
            try db.fetch("action", "SELECT id, at, kind, target, detail FROM action ORDER BY id") { row in
                Action(
                    at: try row.date("at"), kind: try row.value("kind"), target: try row.value("target"),
                    detail: try row.json("detail"))
            }
        }
    }
}
