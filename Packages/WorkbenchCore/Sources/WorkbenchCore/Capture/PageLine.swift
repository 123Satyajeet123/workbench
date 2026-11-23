import Foundation
import GRDB

/// One line of a web page the person had on screen, as the app reads it from the evidence store: the site it was on, the
/// page's title, and the words, with the label and authority the writer gave it.
public struct PageLine: Equatable, Sendable {
    /// The row number of the evidence line: the number a model cites.
    public var id: Int64
    public var lineID: Data
    public var provenance: Provenance?
    /// The page address, without its query and fragment.
    public var address: String
    /// The site the grant names.
    public var site: String
    public var title: String
    public var seenAt: Date
    public var text: String

    public init(
        id: Int64, lineID: Data, provenance: Provenance? = nil, address: String, site: String, title: String,
        seenAt: Date, text: String
    ) {
        self.id = id
        self.lineID = lineID
        self.provenance = provenance
        self.address = address
        self.site = site
        self.title = title
        self.seenAt = seenAt
        self.text = text
    }

    /// The part a stored line is. Nil for a line that is no page line.
    init?(_ line: StoredLine) {
        let prefix = Store.grantID(kind: .screenText, label: "")
        guard !line.isTombstone, line.grantID.hasPrefix(prefix) else { return nil }
        self.init(
            id: line.number, lineID: line.lineID, provenance: line.provenance, address: line.container,
            site: String(line.grantID.dropFirst(prefix.count)), title: line.coordinate ?? "",
            seenAt: line.time ?? .distantPast, text: line.text)
    }

    /// One numbered line a machine reads, with the label and authority the store gave it: the site, the page's title
    /// and the text on screen.
    public var evidence: Evidence {
        Evidence(
            id: id, start: seenAt, line: "\(site) — \(title): \(text)", quotable: [text], lineID: lineID,
            provenance: provenance)
    }

    /// The page lines of a day a machine reads: only those on the named sites, a repeated text of one page once, earliest
    /// first up to the budget. `leftOut` counts the lines past the budget.
    public static func reading(_ lines: [PageLine], sites: [String], budget: Int = WebPage.budget) -> (
        pages: [PageLine], leftOut: Int
    ) {
        let named = Set(sites)
        var seen = Set<String>()
        var kept: [PageLine] = []
        var used = 0
        var leftOut = 0
        for line in lines.sorted(by: { $0.id < $1.id })
        where CapturePolicy.isSite("https://" + line.site, in: named)
            && seen.insert(line.address + "\n" + line.text).inserted
        {
            guard used + line.text.count <= budget else {
                leftOut += 1
                continue
            }
            used += line.text.count
            kept.append(line)
        }
        return (kept, leftOut)
    }
}

extension Queries {
    /// The page lines first seen in `start..<end`: the current version of each line, oldest first.
    public func pageLines(from start: Date, to end: Date) throws -> [PageLine] {
        let prefix = Store.grantID(kind: .screenText, label: "")
        return try reader.read { db in
            try StoredLine.fetchAll(
                db,
                sql: """
                    SELECT e.id AS number, \(StoredLine.columns) FROM evidence e
                    WHERE substr(e.grant_id, 1, length(?)) = ? AND e.first_seen >= ? AND e.first_seen < ?
                        AND e.id = (SELECT v.id FROM evidence v WHERE v.entity_key = e.entity_key
                            ORDER BY v.last_seen DESC, v.id DESC LIMIT 1)
                    ORDER BY e.id
                    """,
                arguments: [prefix, prefix, start.millisecondsSince1970, end.millisecondsSince1970]
            ).compactMap(PageLine.init)
        }
    }
}
