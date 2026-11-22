import Foundation
import GRDB

public struct WorkEvent: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case create, title, stage, note, link, claim, release, archive
    }

    public var id: String
    public var object: String
    public var author: String
    public var clock: Int
    public var at: Date
    public var kind: Kind
    public var text: String
    public var replaces: [String]
    public var item: LinkedItem?

    public init(
        id: String = UUID().uuidString, object: String, author: String, clock: Int, at: Date, kind: Kind,
        text: String = "", replaces: [String] = [], item: LinkedItem? = nil
    ) {
        self.id = id
        self.object = object
        self.author = author
        self.clock = clock
        self.at = at
        self.kind = kind
        self.text = text
        self.replaces = replaces
        self.item = item
    }
}

public struct LinkedItem: Codable, Sendable, Equatable {
    public var machine: String
    public var day: String
    public var columns: [String]
    public var fields: [String: String]
    public var quote: String
    public var state: Mark
    public var source: SourceKind?
    public var audience: [String]
    public var task: String?
    public var itemID: Int64?

    public init(machine: Machine, item: Item, audience: [String]) {
        self.machine = machine.name
        task = machine.task
        itemID = item.id
        source = item.source
        day = item.day.description
        columns = machine.spec.fields.map(\.name)
        fields = item.fields
        quote = item.quote
        state = item.state
        self.audience = audience
    }

    public func isVisible(to person: String) -> Bool { audience.contains(person) }
}

public struct WorkObject: Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: String
    public var title: String
    public var stages: [String]
    public var stageHeads: [String]
    public var holder: String?
    public var alsoClaimed: [String]
    public var notes: [WorkEvent]
    public var items: [(event: WorkEvent, item: LinkedItem)]
    public var history: [WorkEvent]
    public var archived: Bool

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.stages == rhs.stages && lhs.holder == rhs.holder
            && lhs.history == rhs.history && lhs.archived == rhs.archived
    }

    public static func fold(_ events: [WorkEvent], viewer: String) -> [WorkObject] {
        let ordered = events.sorted { ($0.clock, $0.author, $0.id) < ($1.clock, $1.author, $1.id) }
        return Dictionary(grouping: ordered, by: \.object).compactMap { id, events in
            guard let created = events.first(where: { $0.kind == .create }) else { return nil }
            return object(id, kind: created.text, events: events, viewer: viewer)
        }
        .sorted { ($0.history.last?.clock ?? 0) > ($1.history.last?.clock ?? 0) }
    }

    private static func object(_ id: String, kind: String, events: [WorkEvent], viewer: String) -> WorkObject {
        let stageEvents = events.filter { $0.kind == .stage }
        let replaced = Set(stageEvents.flatMap(\.replaces))
        let heads = stageEvents.filter { !replaced.contains($0.id) }
        var open: [String] = []
        for event in events {
            switch event.kind {
            case .claim where !open.contains(event.author): open.append(event.author)
            case .release: open.removeAll { $0 == event.author }
            default: break
            }
        }
        return WorkObject(
            id: id, kind: kind, title: events.last { $0.kind == .title }?.text ?? "",
            stages: Array(Set(heads.map(\.text))).sorted(), stageHeads: heads.map(\.id), holder: open.first,
            alsoClaimed: Array(open.dropFirst()), notes: events.filter { $0.kind == .note },
            items: events.compactMap { event in
                guard event.kind == .link, let item = event.item, item.isVisible(to: viewer) else { return nil }
                return (event, item)
            },
            history: events, archived: events.contains { $0.kind == .archive })
    }
}

extension WorkObject {
    public static let dealStages = [
        "Inbox", "Screen", "In conversation", "Action required", "Founder meeting", "Diligence", "Decision",
        "Invested", "Rejected",
    ]
    public static let actionRequired = "Action required"
    public static let afterAction = "In conversation"
}

public enum WorkLog {
    public static let subfolder = "events"

    public static func fileName(author: String) -> String { TeamFolder.safe(author) + ".jsonl" }

    public static func write(_ events: [WorkEvent], author: String, to team: URL) throws {
        let folder = team.appending(path: subfolder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let lines = try events.filter { $0.author == author }.sorted { ($0.clock, $0.id) < ($1.clock, $1.id) }
            .map { try Coding.json($0) }
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(
            to: folder.appending(path: fileName(author: author)), options: .atomic)
    }

    public static func read(from team: URL) -> (events: [WorkEvent], unreadable: [String]) {
        let folder = team.appending(path: subfolder)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        var events: [WorkEvent] = []
        var unreadable: [String] = []
        for file in files where file.pathExtension == "jsonl" {
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            let lines = text.split(separator: "\n").map(String.init)
            let decoded = lines.compactMap { try? Coding.value(WorkEvent.self, from: $0) }
            if decoded.count != lines.count { unreadable.append(file.lastPathComponent) }
            events += decoded
        }
        return (events, unreadable.sorted())
    }
}

extension Store {
    public func append(_ events: [WorkEvent]) throws {
        try writer.write { db in
            for event in events {
                try db.execute(
                    sql: """
                        INSERT OR IGNORE INTO work_event(event_id, object, author, clock, at, kind, body)
                        VALUES (?,?,?,?,?,?,?)
                        """,
                    arguments: [
                        event.id, event.object, event.author, event.clock, event.at.stored, event.kind.rawValue,
                        try Coding.json(event),
                    ])
            }
        }
    }
}

extension Queries {
    public func workEvents() throws -> [WorkEvent] {
        try reader.read { db in
            try db.fetch("work_event", "SELECT id, body FROM work_event ORDER BY clock, id") { row in
                try row.json("body", as: WorkEvent.self)
            }
        }
    }

    public func nextClock() throws -> Int {
        try reader.read { db in try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(clock), 0) FROM work_event") ?? 0 } + 1
    }
}
