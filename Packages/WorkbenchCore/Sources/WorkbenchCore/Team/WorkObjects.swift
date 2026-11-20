import Foundation
import GRDB

/// One act on a shared work object, such as a deal, by one person. Events are never edited: each person appends to
/// their own log, every Mac keeps the union by id, and the object is a fold over them (research 26 §8–§9).
public struct WorkEvent: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case create, title, stage, note, link, claim, release, archive
    }

    public var id: String
    public var object: String
    public var author: String
    /// Lamport clock: higher than every event the author had seen when writing it. Orders history across Macs.
    public var clock: Int
    public var at: Date
    public var kind: Kind
    /// The title, the stage, the note, or the object's kind (for create).
    public var text: String
    /// For a stage: the stage events this one replaces, as the author saw them. Two stage events that do not
    /// replace each other are concurrent, and both stay until someone replaces both.
    public var replaces: [String]
    /// For a link: the item, as it was when linked.
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

/// An item as linked to a work object: its fields, quote and its author's mark, and who may read it.
public struct LinkedItem: Codable, Sendable, Equatable {
    public var machine: String
    public var day: String
    public var columns: [String]
    public var fields: [String: String]
    public var quote: String
    public var state: Mark
    /// The consent kind of the item's source. Nil in an event written before the field existed: unknown.
    public var source: SourceKind?
    /// Everyone who could already read the item's source when it was linked, by name.
    public var audience: [String]
    /// The machine's task and the item's id in its author's store. Nil in an event written before the fields
    /// existed. The id means something only on the author's Mac.
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

/// A work object as one viewer sees it, folded from everyone's events.
public struct WorkObject: Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: String
    public var title: String
    /// The current stage; more than one when people moved it at the same time without seeing each other's move.
    public var stages: [String]
    /// The stage events still standing: a new move replaces all of them.
    public var stageHeads: [String]
    /// Who holds it (the earliest open claim), and others who claimed it too.
    public var holder: String?
    public var alsoClaimed: [String]
    public var notes: [WorkEvent]
    /// Linked items the viewer may read, with the event that linked each.
    public var items: [(event: WorkEvent, item: LinkedItem)]
    public var history: [WorkEvent]
    public var archived: Bool

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.stages == rhs.stages && lhs.holder == rhs.holder
            && lhs.history == rhs.history && lhs.archived == rhs.archived
    }

    /// Every object in `events`, as `viewer` may see it. Events are taken in Lamport order, ties by author and id.
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
    /// A deal's stages (Hustle Fund's, research 27 §1.1, with the three a VC analyst asked for). Stages are data:
    /// a team may use its own, and the board still shows a deal in a stage that is not listed.
    public static let dealStages = [
        "Inbox", "Screen", "In conversation", "Action required", "Founder meeting", "Diligence", "Decision",
        "Invested", "Rejected",
    ]
    public static let actionRequired = "Action required"
    public static let afterAction = "In conversation"
}

/// Each person's events on work objects, one file per person in the team folder, one JSON event per line. A person
/// rewrites only their own file; every Mac reads all of them.
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

    /// Every event in every person's file, and the files with a line that could not be read.
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
    /// Keeps an event once, whoever wrote it. Importing the same log again changes nothing.
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

    /// The clock a new event takes: one more than any event this Mac has seen.
    public func nextClock() throws -> Int {
        try reader.read { db in try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(clock), 0) FROM work_event") ?? 0 } + 1
    }
}
