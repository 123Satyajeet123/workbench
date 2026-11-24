import Foundation
import GRDB
import Kernel
import Lines

extension StoredLine {
    /// What the person agreed to for this line: the kind and label its grant names.
    public var consent: Consent? {
        let parts = grantID.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let kind = SourceKind(rawValue: String(parts[0])) else { return nil }
        return Consent(kind: kind, label: String(parts[1]))
    }

    /// The line as a model reads it: who said it, where in a file, and the words.
    public var evidence: Evidence {
        let place = coordinate.flatMap { try? Coding.value(FilePlace.self, from: $0) }
            .map { " — \($0.file) page \($0.page)" }
        return Evidence(
            id: number, start: time ?? .distantPast,
            line: "\(actor ?? "Unknown")\(place ?? "")\(forwarded ? " (quoted)" : ""): \(text)", quotable: [text],
            lineID: lineID, provenance: provenance, consent: consent)
    }
}

extension Queries {
    /// The evidence lines of a deal, whatever source they came from: the lines of the items its `author` linked, and
    /// what the person added to it by hand (files and typed notes). Oldest first, each line once.
    public func evidence(of deal: WorkObject, author: String) throws -> [Evidence] {
        let linked = deal.items.filter { $0.event.author == author }.compactMap(\.item.itemID)
        return try reader.read { db in
            var lines = try Self.handLines(in: deal.id, db)
            for item in linked { lines += try Self.lines(ofItem: item, db) }
            var seen: Set<Data> = []
            return lines.filter { seen.insert($0.lineID).inserted }
                .sorted { ($0.time ?? .distantPast, $0.number) < ($1.time ?? .distantPast, $1.number) }
                .map(\.evidence)
        }
    }

    /// The stored line with this id; nil when none is stored.
    static func line(withID id: LineID, in db: Database) throws -> StoredLine? {
        try StoredLine.fetchAll(
            db,
            sql: "SELECT e.id AS number, \(StoredLine.columns) FROM evidence e WHERE e.line_id = ?",
            arguments: [Data(id.bytes)]
        ).first
    }

    private static let currentVersion = """
        e.id = (SELECT v.id FROM evidence v WHERE v.entity_key = e.entity_key ORDER BY v.last_seen DESC, v.id DESC LIMIT 1)
        """

    private static func handLines(in container: String, _ db: Database) throws -> [StoredLine] {
        let kinds = SourceKind.byHand.map { Store.grantID(kind: $0, label: "") }
        return try StoredLine.fetchAll(
            db,
            sql: """
                SELECT e.id AS number, \(StoredLine.columns) FROM evidence e WHERE e.container = ?
                    AND e.tombstone = 0 AND \(currentVersion)
                    AND substr(e.grant_id, 1, instr(e.grant_id, ':')) IN (SELECT value FROM json_each(?))
                """, arguments: [container, try Coding.json(kinds)])
    }

    /// The lines a fact rests on: the lines it cites, and the lines around them that its source says belong to it.
    private static func lines(ofItem id: Int64, _ db: Database) throws -> [StoredLine] {
        let cited = try citedLines(ofItem: id, db)
        var lines: [StoredLine] = []
        for (place, group) in Dictionary(grouping: cited, by: { [$0.container, $0.grantID] }) {
            let reach = group[0].consent.flatMap { SourceRegistry.descriptor(consent: $0.kind) }?.evidenceReach
            let all = try StoredLine.fetchAll(
                db,
                sql: """
                    SELECT e.id AS number, \(StoredLine.columns) FROM evidence e WHERE e.container = ?
                        AND e.grant_id = ? AND e.tombstone = 0 AND \(currentVersion) ORDER BY e.event_time, e.id
                    """, arguments: StatementArguments(place))
            lines += reach.map { around(group, in: all, reach: $0) } ?? all
        }
        return lines
    }

    private static func around(_ cited: [StoredLine], in all: [StoredLine], reach: Int) -> [StoredLine] {
        let hits = Set(cited.map(\.lineID))
        let places = all.indices.filter { hits.contains(all[$0].lineID) }
        return all.indices.filter { index in places.contains { abs($0 - index) <= reach } }.map { all[$0] }
    }

    /// The lines a fact cites, through the window of the run that made it, or for a fact made before runs kept their
    /// windows, through the old citation ids.
    private static func citedLines(ofItem id: Int64, _ db: Database) throws -> [StoredLine] {
        let windowed = try StoredLine.fetchAll(
            db,
            sql: """
                SELECT e.id AS number, \(StoredLine.columns) FROM item JOIN run_line w ON w.run_id = item.run_id
                    AND w.ordinal BETWEEN item.cite_first AND item.cite_last JOIN evidence e ON e.line_id = w.line_id
                WHERE item.id = ?
                """, arguments: [id])
        guard windowed.isEmpty else { return windowed }
        return try LegacySpace.byKind.flatMap { kind, space in
            try StoredLine.fetchAll(
                db,
                sql: """
                    SELECT e.id AS number, \(StoredLine.columns) FROM item JOIN evidence_legacy l ON l.space = ?
                        AND l.ref BETWEEN item.cite_first AND item.cite_last JOIN evidence e ON e.line_id = l.line_id
                    WHERE item.id = ? AND item.source = ?
                        AND NOT EXISTS (SELECT 1 FROM run_line WHERE run_id = item.run_id)
                    """, arguments: [space.rawValue, id, kind.rawValue])
        }
    }
}
