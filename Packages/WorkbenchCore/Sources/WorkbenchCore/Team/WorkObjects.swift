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
    /// The title, the stage id, the note, or the object's type id (for create). An older stage event holds the stage label.
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

/// What the events of one object say about it: its type, its latest name, and when it was first archived.
struct EventSummary: Equatable {
    var type: TypeID
    var name: String
    var archivedAt: Date?

    /// Nil when the events hold no `create`, so the object is not known.
    init?(_ events: [WorkEvent]) {
        let ordered = events.sorted(by: WorkEvent.isBefore)
        guard let created = ordered.first(where: { $0.kind == .create }) else { return nil }
        type = created.text
        name = ordered.last { $0.kind == .title }?.text ?? ""
        archivedAt = ordered.first { $0.kind == .archive }?.at
    }
}

extension WorkEvent {
    /// Lamport order, ties by author and id.
    static func isBefore(_ lhs: WorkEvent, _ rhs: WorkEvent) -> Bool {
        (lhs.clock, lhs.author, lhs.id) < (rhs.clock, rhs.author, rhs.id)
    }
}

/// A work object: one node of the tree, of any kind. A folder, a page, a machine's page, a deal and a project are one
/// entity, with one parent and one place among its siblings. The fields after `archivedAt` are what the events of a
/// shared object add, folded from everyone's events as one viewer may see them; a folder has none.
public struct WorkObject: Sendable, Equatable, Identifiable {
    public var id: WorkObjectID
    public var kind: String
    public var type: ObjectType
    public var parentID: WorkObjectID?
    /// Orders the siblings that share a parent.
    public var position: Double
    public var name: String
    public var archivedAt: Date?
    /// The ids of the current stage; more than one when people moved it at the same time without seeing each
    /// other's move. Ordered as the type orders its stages.
    public var stages: [StageID]
    /// The stage events still standing: a new move replaces all of them.
    public var stageHeads: [String]
    /// Who holds it (the earliest open claim), and others who claimed it too.
    public var holder: String?
    public var alsoClaimed: [String]
    public var notes: [WorkEvent]
    /// Linked items the viewer may read, with the event that linked each.
    public var items: [(event: WorkEvent, item: LinkedItem)]
    public var history: [WorkEvent]

    public var archived: Bool { archivedAt != nil }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.parentID == rhs.parentID && lhs.position == rhs.position
            && lhs.stages == rhs.stages && lhs.holder == rhs.holder && lhs.history == rhs.history
            && lhs.archivedAt == rhs.archivedAt
    }

    /// Every object the events make, as `viewer` may see it. The objects have no place in the tree: a place is a row.
    public static func fold(
        _ events: [WorkEvent], viewer: String, type typeFor: (String) -> ObjectType = ObjectTypes.type(for:)
    ) -> [WorkObject] {
        Dictionary(grouping: events, by: \.object).compactMap { id, events in
            guard let summary = EventSummary(events) else { return nil }
            let node = WorkObjectRow(
                id: id, type: summary.type, parentID: nil, position: 0, name: summary.name,
                archivedAt: summary.archivedAt)
            return WorkObject(node, events: events, viewer: viewer, type: typeFor(summary.type))
        }
        .sorted { ($0.history.last?.clock ?? 0) > ($1.history.last?.clock ?? 0) }
    }
}

extension WorkObject {
    /// A node of the tree with the events that belong to it, folded as `viewer` may see them.
    init(_ node: WorkObjectRow, events: [WorkEvent], viewer: String, type: ObjectType? = nil) {
        let ordered = events.sorted(by: WorkEvent.isBefore)
        let type = type ?? ObjectTypes.type(for: node.type)
        let stageEvents = ordered.filter { $0.kind == .stage }
        let replaced = Set(stageEvents.flatMap(\.replaces))
        let heads = stageEvents.filter { !replaced.contains($0.id) }
        var open: [String] = []
        for event in ordered {
            switch event.kind {
            case .claim where !open.contains(event.author): open.append(event.author)
            case .release: open.removeAll { $0 == event.author }
            default: break
            }
        }
        self.init(
            id: node.id, kind: type.id, type: type, parentID: node.parentID, position: node.position,
            name: node.name, archivedAt: node.archivedAt, stages: Self.standing(heads, in: type).map(\.id),
            stageHeads: heads.map(\.id), holder: open.first, alsoClaimed: Array(open.dropFirst()),
            notes: ordered.filter { $0.kind == .note },
            items: ordered.compactMap { event in
                guard event.kind == .link, let item = event.item, item.isVisible(to: viewer) else { return nil }
                return (event, item)
            }, history: ordered)
    }
}

extension WorkObject {
    private static func standing(_ heads: [WorkEvent], in type: ObjectType) -> [StageDef] {
        Dictionary(heads.map { (type.resolveStage($0.text).id, type.resolveStage($0.text)) }) { first, _ in first }
            .values.sorted { ($0.order, $0.id) < ($1.order, $1.id) }
    }

    public var standingStages: [StageDef] { stages.map(type.resolveStage) }
    public var stageLabels: [String] { standingStages.map(\.label) }
    public var meanings: Set<Meaning> { Set(standingStages.map(\.meaning)) }
}

extension Store {
    /// Keeps an event once, whoever wrote it. Importing the same log again changes nothing. The objects the events
    /// name get their node in the tree, or their name and archive time updated, in the same transaction.
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
            try WorkObjectRows.project(db, objects: events.map(\.object))
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
