import Foundation
import GRDB

extension Store {
    /// How long a finding of facts counts as told: a repeat of the same choices and facts inside this many days is not
    /// added.
    static let toldBeforeDays = 14

    /// Stores one reading of a day by one helper. Nothing already stored is deleted or replaced: a fact the founder
    /// closed, hid or marked stays as the founder left it. A reading adds the facts it opens, and the events it
    /// writes on facts (a restatement, a new date, a replacement, a proposal to close, a flag), each with the run,
    /// the line and the quote that show it. A machine with no lifecycle adds no item that repeats one stored before
    /// it, or a finding of facts told before (`toldBeforeDays`). The app picks each new item on its own, with
    /// the chance `AuditPolicy.pickChance`, to ask the founder about, and keeps the chance it had. Each new item is
    /// filed in the folder of its machine; a home the model proposed is filed after it. The grant is asked after the
    /// model ran, so consent withdrawn meanwhile stops the write.
    public func saveReading(
        _ result: HelperReader.Result, of spec: HelperSpec, day: WorkDay, scope: String, grant: CaptureGrant,
        isAudited: ((Int) -> Bool)? = nil
    ) throws {
        try check(grant, kind: spec.source.kind, label: scope.isEmpty ? nil : scope)
        try writer.write { db in
            let known = try knownItems(db, of: spec, day: day, scope: scope)
            let opened: [Int64?] = try result.items.map { item in
                guard
                    !known.contains(where: {
                        SameClaim.holds(item, $0, citation: spec.citation, choices: spec.choiceFields)
                    })
                else { return nil }
                var row = item
                row.day = day
                row.scope = scope
                let id = try Self.insertItem(db, row, at: clock())
                if spec.lifecycle != nil { try reconcileTimers(db, item: id) }
                return id
            }
            for (index, id) in opened.compactMap({ $0 }).enumerated()
            where audits(item: id, of: spec.task, index: index, override: isAudited) {
                try db.execute(
                    sql: "UPDATE item SET asked_with = ? WHERE id = ?", arguments: [AuditPolicy.pickChance, id])
            }
            for proposal in result.homes {
                if let item = opened[proposal.item] { try fileProposal(db, item: item, into: proposal.object) }
            }
            if let run = result.run {
                for link in result.links { try apply(link, opened: opened, run: run, db) }
                try Self.recordYield(db, of: run, kept: result.kept, dropped: result.dropped)
            }
        }
    }

    /// Whether a new item is picked to ask the founder about: by the audit design of its task, unless a test chose the
    /// picks by the item's place in its reading.
    func audits(item: Int64, of task: String, index: Int, override: ((Int) -> Bool)?) -> Bool {
        if let choose = override ?? isAudited { return choose(index) }
        return AuditPolicy.pick(design: AuditPolicy.design(of: task), item: item)
    }

    /// The items a new item of a machine with no lifecycle may repeat. A machine with a lifecycle names the fact it
    /// restates, so it has none.
    private func knownItems(_ db: Database, of spec: HelperSpec, day: WorkDay, scope: String) throws -> [Item] {
        guard spec.lifecycle == nil else { return [] }
        return spec.citation == .facts
            ? try Queries.items(db, of: spec.task, since: day.adding(days: -Self.toldBeforeDays))
            : try Queries.items(db, of: spec.task, day: day, scope: scope)
    }

    /// The one place a row enters `item`, with every column. It writes no event: the `item_opens` trigger records the
    /// opening. `origin` is the field of a fact that code makes from a work object; the fact is filed under that
    /// object.
    static func insertItem(
        _ db: Database, _ item: Item, at now: Date, origin: HelperSpec.Field? = nil
    ) throws -> Int64 {
        try db.execute(
            sql: """
                INSERT INTO item(task, run_id, day, scope, source, cite_first, cite_last, start_at, end_at, fields,
                    quote, created_at, quote_line, quote_part, quote_start, quote_end, label, authority)
                VALUES (\(databaseQuestionMarks(count: 18)))
                """,
            arguments: [
                item.task, item.run, item.day.description, item.scope, item.source.rawValue, item.citeFirst,
                item.citeLast, item.start.stored, item.end.stored, try Coding.json(item.fields), item.quote,
                now.stored, item.quoteSpan?.line, item.quoteSpan?.part, item.quoteSpan?.start, item.quoteSpan?.end,
                try item.label.map { try Coding.json(StoredLabel($0)) }, item.authority.rawValue,
            ])
        let id = db.lastInsertedRowID
        try derive(try DerivedSources.ofItem(id, in: db) + DerivedSources.ofOpening(of: id, in: db), at: now, in: db)
        try FactFiling.fileInDefaultHomes(db, item: id, origin: origin)
        return id
    }

    /// Writes the event of one link. An event on a fact this reading did not open, or opened as a repeat, is not
    /// written when its fact is not stored.
    private func apply(_ link: Link, opened: [Int64?], run: RunID, _ db: Database) throws {
        let fact: Int64?
        switch link.subject {
        case .stored(let id): fact = id
        case .opened(let index): fact = opened[index]
        }
        guard let fact else { return }
        var due: String?
        var outcome: String?
        var successor: Int64?
        switch link.effect {
        case .restate, .flag: break
        case .dueChanged(let changed): due = try Coding.json(changed)
        case .supersede(let index): successor = opened[index]
        case .closeProposed(let proposed): outcome = proposed
        }
        try addEvent(
            db, item: fact, kind: link.kind, outcome: outcome, due: due, successor: successor, at: link.at,
            by: (run: run, line: link.line, quote: link.quote))
    }

    /// A trial reads past days with a new brief and keeps its items apart from the machine's own. A new trial of the
    /// same machine starts from none of the old trial's items; the machine's own items are never touched.
    public func discardTrialItems(of task: String) throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM item WHERE task = ?", arguments: [Trial.task(of: task)])
        }
    }

    /// The founder closes an open item by hand: a new event, so a later reopening and the model's proposals stay on
    /// record.
    public func close(item id: Int64, as outcome: String, surface: MarkSurface) throws {
        try writer.write { db in
            try addEvent(db, item: id, kind: .close, outcome: outcome, at: clock(), surface: surface)
        }
    }

    /// The founder agrees with the model's proposal to close an item: a close with the outcome it proposed, valid
    /// when the founder acts. The proposal stays on record.
    public func confirmClose(item id: Int64, surface: MarkSurface) throws {
        try writer.write { db in
            guard
                let outcome = try String.fetchOne(
                    db, sql: "SELECT proposal_outcome FROM item_proposal WHERE item_id = ?", arguments: [id])
            else { throw StoreError.noCloseProposal(item: id) }
            try addEvent(db, item: id, kind: .close, outcome: outcome, at: clock(), surface: surface)
        }
    }

    public func reopen(item id: Int64, surface: MarkSurface) throws {
        try writer.write { db in try addEvent(db, item: id, kind: .reopen, at: clock(), surface: surface) }
    }

    /// The founder says a fact was never one.
    public func withdraw(item id: Int64, surface: MarkSurface) throws {
        try writer.write { db in try addEvent(db, item: id, kind: .withdraw, at: clock(), surface: surface) }
    }

    func addEvent(
        _ db: Database, item: Int64, kind: EventKind, outcome: String? = nil, until: Date? = nil, due: String? = nil,
        successor: Int64? = nil, handedTo: String? = nil, batch: Int64? = nil, at: Date,
        surface: MarkSurface? = nil, by model: (run: RunID, line: Int64, quote: String)? = nil
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO item_event(item_id, kind, outcome, line_id, quote, valid_at, recorded_at, run_id, actor,
                    until, due, successor, surface, handed_to, batch_id) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """,
            arguments: [
                item, kind.rawValue, outcome, model?.line, model?.quote, at.stored, clock().stored, model?.run,
                model == nil ? "person" : "model", until?.stored, due, successor, surface?.rawValue, handedTo, batch,
            ])
        if model != nil {
            try Self.derive(try DerivedSources.ofEvent(db.lastInsertedRowID, in: db), at: clock(), in: db)
        }
        if Self.changesTimers.contains(kind) { try reconcileTimers(db, item: item) }
    }

    /// The events after which the timers of a fact may differ: a new due time, and each that ends or reopens it.
    private static let changesTimers = EventKind.statusKinds + [.dueChanged]

    /// Marks are history: each one is a new row, and the latest is the item's state. Taking a mark back is a mark. A
    /// mark on an item the app picked is an audit mark, with the chance the item had.
    public func mark(item id: Int64, as mark: Mark) throws {
        try writer.write { db in try addMark(db, item: id, mark) }
    }

    func addMark(_ db: Database, item id: Int64, _ mark: Mark) throws {
        try db.execute(
            sql: """
                INSERT INTO mark(item_id, ts, state, origin, asked_with)
                SELECT id, ?, ?, CASE WHEN asked_with IS NULL THEN 'voluntary' ELSE 'audit' END, COALESCE(asked_with, 1)
                FROM item WHERE id = ?
                """, arguments: [clock().stored, mark.rawValue, id])
    }
}

extension Queries {
    static let itemColumns = """
        id, task, day, scope, source, cite_first, cite_last, start_at, end_at, fields, quote, state, run_id, asked_with,
        status_kind, status_outcome, status_quote, status_at, hiding_kind, hiding_until, source_deleted, quote_line,
        quote_part, quote_start, quote_end, label, authority, due_value, proposal_outcome, proposal_quote, proposal_at,
        handoff_to
        """
    /// Items with their mark, their status, their latest hide, snooze or unhide, the date their latest line gave, and
    /// the proposal to close that nobody has acted on, and the person it was handed to.
    static let itemRows = """
        item_mark LEFT JOIN item_status ON item_status.item_id = item_mark.id
            LEFT JOIN item_hiding ON item_hiding.item_id = item_mark.id
            LEFT JOIN item_due ON item_due.item_id = item_mark.id
            LEFT JOIN item_proposal ON item_proposal.item_id = item_mark.id
            LEFT JOIN item_handoff ON item_handoff.item_id = item_mark.id
        """

    /// One item, inside a transaction already open on `db`.
    static func item(_ db: Database, id: Int64) throws -> Item? {
        try db.fetch("item", "SELECT \(itemColumns) FROM \(itemRows) WHERE id = ?", [id], as: Item.init(row:)).first
    }

    /// The items of a machine still open: of a value its lifecycle keeps open, not rejected, and not closed since.
    /// The newest `limit`, oldest first. With `day`, the items as they stood on that day: opened by the day's end and
    /// not ended, by valid time, before the day started.
    public func openItems(
        of task: String, lifecycle: HelperSpec.Lifecycle, asOf day: WorkDay? = nil, limit: Int = 300
    ) throws -> [Item] {
        guard !lifecycle.open.isEmpty else { return [] }
        let values = databaseQuestionMarks(count: lifecycle.open.count)
        let status: String
        var bounds = StatementArguments()
        if let day {
            status = """
                day <= ? AND COALESCE((SELECT kind FROM item_event WHERE item_id = item_mark.id
                    AND kind IN ('supersede','close','reopen','withdraw') AND valid_at < ?
                    ORDER BY valid_at DESC, recorded_at DESC, id DESC LIMIT 1), 'open') NOT IN ('supersede','close','withdraw')
                """
            bounds = [day.description, day.start.stored]
        } else {
            status = "(status_kind IS NULL OR status_kind = 'reopen')"
        }
        let arguments =
            StatementArguments([task, "$.\(lifecycle.field)"]) + StatementArguments(lifecycle.open) + bounds + [limit]
        return try reader.read { db in
            try db.fetch(
                "item",
                """
                SELECT \(Self.itemColumns) FROM \(Self.itemRows)
                WHERE task = ? AND state <> 'rejected' AND json_extract(fields, ?) IN (\(values)) AND \(status)
                ORDER BY day DESC, start_at DESC, id DESC LIMIT ?
                """, arguments, as: Item.init(row:)
            ).reversed()
        }
    }

    /// The open items a machine's reader sees: its own, or, when it has no lifecycle, those of the machine it
    /// follows and the actions deals wait for; as of `day` when given. None when it follows no machine that exists.
    public func openItems(readBy spec: HelperSpec, asOf day: WorkDay? = nil) throws -> [Item] {
        if let lifecycle = spec.lifecycle { return try openItems(of: spec.task, lifecycle: lifecycle, asOf: day) }
        guard let follows = spec.follows else { return [] }
        let machines = try machines()
        guard let lifecycle = machines.first(where: { $0.task == follows })?.spec.lifecycle else { return [] }
        let alike = machines.filter { $0.task != follows && $0.spec.lifecycle == lifecycle }.map(\.task)
        return try ([follows] + alike).flatMap { try openItems(of: $0, lifecycle: lifecycle, asOf: day) }
            + openDealActions(asOf: day)
    }

    /// A machine's items that ended (closed, replaced or withdrawn) between two times, by valid time, oldest first.
    public func closedItems(of task: String, from: Date, to: Date) throws -> [Item] {
        try reader.read { db in
            try db.fetch(
                "item",
                """
                SELECT \(Self.itemColumns) FROM \(Self.itemRows)
                WHERE task = ? AND status_kind IN ('supersede','close','withdraw') AND status_at >= ? AND status_at < ?
                ORDER BY status_at, id
                """, [task, from.stored, to.stored], as: Item.init(row:))
        }
    }

    /// A machine's open items that a model read as closed, and that nobody has acted on since. A person confirms
    /// each with `confirmClose`, or ignores it with a reopen.
    public func closeProposals(of task: String) throws -> [Item] {
        try reader.read { db in
            try db.fetch(
                "item",
                """
                SELECT \(Self.itemColumns) FROM \(Self.itemRows)
                WHERE task = ? AND proposal_outcome IS NOT NULL AND (status_kind IS NULL OR status_kind = 'reopen')
                ORDER BY proposal_at, id
                """, [task], as: Item.init(row:))
        }
    }

    public func items(of task: String, day: WorkDay, scope: String) throws -> [Item] {
        try reader.read { db in try Self.items(db, of: task, day: day, scope: scope) }
    }

    /// The same read inside a transaction already open on `db`.
    static func items(_ db: Database, of task: String, day: WorkDay, scope: String) throws -> [Item] {
        try db.fetch(
            "item",
            "SELECT \(itemColumns) FROM \(itemRows) WHERE task = ? AND day = ? AND scope = ? ORDER BY start_at, id",
            [task, day.description, scope], as: Item.init(row:))
    }

    /// The items with these ids, oldest first.
    public func items(ids: [Int64]) throws -> [Item] {
        try reader.read { db in
            try db.fetch(
                "item",
                "SELECT \(Self.itemColumns) FROM \(Self.itemRows) WHERE id IN (SELECT value FROM json_each(?)) ORDER BY id",
                [try Coding.json(ids)], as: Item.init(row:))
        }
    }

    /// One machine's items on one day, in every chat scope, in time order.
    public func items(of task: String, on day: WorkDay) throws -> [Item] {
        try reader.read { db in
            try db.fetch(
                "item",
                "SELECT \(Self.itemColumns) FROM \(Self.itemRows) WHERE task = ? AND day = ? ORDER BY start_at, id",
                [task, day.description], as: Item.init(row:))
        }
    }

    /// One machine's items since `day`, oldest first, in every scope.
    public func items(of task: String, since day: WorkDay) throws -> [Item] {
        try reader.read { db in try Self.items(db, of: task, since: day) }
    }

    static func items(_ db: Database, of task: String, since day: WorkDay) throws -> [Item] {
        try db.fetch(
            "item",
            "SELECT \(itemColumns) FROM \(itemRows) WHERE task = ? AND day >= ? ORDER BY day, start_at, id",
            [task, day.description], as: Item.init(row:))
    }

    /// Every machine's items still waiting for a mark since `day`: the app's random picks first, then the newest days.
    public func waitingItems(since day: WorkDay) throws -> [Item] {
        try reader.read { db in
            try db.fetch(
                "item",
                """
                SELECT \(Self.itemColumns) FROM \(Self.itemRows) WHERE state = 'proposed' AND day >= ?
                ORDER BY asked_with IS NULL, day DESC, start_at, id
                """, [day.description], as: Item.init(row:))
        }
    }
}

extension Item {
    init(row: Row) throws {
        self.init(
            id: try row.optionalValue("id"), task: try row.value("task"), day: try row.workDay("day"),
            scope: try row.value("scope"), source: try row.enumeration("source"),
            citeFirst: try row.value("cite_first"),
            citeLast: try row.value("cite_last"), start: try row.date("start_at"), end: try row.date("end_at"),
            fields: try row.json("fields"), quote: try row.value("quote"), state: try row.enumeration("state"),
            run: try row.optionalValue("run_id"), askedWith: try row.optionalValue("asked_with"))
        isSourceDeleted = try row.value("source_deleted") as Int == 1
        authority = try row.enumeration("authority")
        label = try row.optionalValue("label").map { (text: String) in
            try Coding.value(StoredLabel.self, from: text).label()
        }
        if let line: Int64 = try row.optionalValue("quote_line") {
            quoteSpan = QuoteSpan(
                line: line, part: try row.value("quote_part"), start: try row.value("quote_start"),
                end: try row.value("quote_end"))
        }
        if let kind = try row.optionalValue("status_kind") as String?, kind != EventKind.reopen.rawValue {
            closed = Closed(
                outcome: try row.value("status_outcome"), quote: try row.optionalValue("status_quote"),
                at: try row.date("status_at"))
        }
        if let outcome: String = try row.optionalValue("proposal_outcome") {
            proposedClose = Closed(
                outcome: outcome, quote: try row.optionalValue("proposal_quote"), at: try row.date("proposal_at"))
        }
        dueChanged = (try row.optionalValue("due_value") as String?).flatMap { try? Coding.value(Due.self, from: $0) }
        hiding = try Self.hiding(row)
        handedTo = try row.optionalValue("handoff_to")
    }

    private static func hiding(_ row: Row) throws -> Hiding? {
        switch try row.optionalValue("hiding_kind") as String? {
        case "hide": .hidden
        case "snooze": .snoozed(until: try row.date("hiding_until"))
        default: nil
        }
    }
}
