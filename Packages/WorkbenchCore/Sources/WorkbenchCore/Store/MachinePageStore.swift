import Foundation
import GRDB
import Kernel
import Lines

public typealias PageProposalID = Int64

public enum PageStoreError: Error, Equatable {
    /// The request has no words.
    case noRequest
    /// The proposal is decided already, or there is none with this id.
    case notPending(PageProposalID)
    /// The block is not a live block of this page, so it cannot be replaced, removed or moved.
    case notLive(MachineBlockID)
    /// A cited fact has no quote in a stored line, so the block could not be found when that line is erased.
    case noQuoteLine(fact: Int64)
    /// A cited paragraph is not on the page.
    case noParagraph(BlockID)
}

extension Store {
    static let requestLabel = "request"

    /// Writes what a machine proposes for a page, in one transaction: the person's request as a typed evidence line,
    /// the blocks the allowed operations bring in (as `proposed` rows, outside the page order, each with its cites and
    /// its label), and the proposal. The proposal that was pending for the page is discarded in the same transaction,
    /// on `surface`, because the person asked again. Returns the proposal's id.
    @discardableResult
    public func propose(
        _ proposal: PageProposal, on page: WorkObjectID, by machine: Int64, request: String, owner: PersonID,
        surface: MarkSurface = .machinePage
    ) throws -> PageProposalID {
        guard let words = request.cleaned else { throw PageStoreError.noRequest }
        let staged = StagedProposal(proposal.allowed)
        let written = try recordTypedWords(words, label: Self.requestLabel, container: page, owner: owner) {
            line, db in
            try Queries.require(db, page)
            if let pending = try Queries.pendingProposalID(db, of: page) {
                try discardProposal(pending, on: surface, in: db)
            }
            let id = try Self.insertProposal(
                db, staged, of: proposal, page: page, machine: machine, request: line.lineID, at: clock())
            let context = try CiteContext(db, page: page, request: line.lineID, blocks: staged.blocks.map(\.block))
            for (blockID, block) in staged.blocks {
                try Self.insertBlock(
                    db, blockID, block, page: page, proposal: id, run: proposal.run, context, at: clock())
            }
            return id
        }
        guard let written else { throw PageStoreError.noRequest }
        return written
    }

    /// Makes the proposed blocks of a pending proposal live, in one transaction. A block enters the page order after
    /// its place; a block that replaces one takes its place and the old one stays as `replaced`; a removed block leaves
    /// the order. An insert whose paragraph was joined to another one goes after the paragraph that holds its words
    /// now, and one whose place is gone goes last.
    public func accept(proposal id: PageProposalID, surface: MarkSurface) throws {
        try writer.write { db in
            let pending = try Self.pending(id, in: db)
            let container = try Self.container(of: pending.page)
            var order = try EvidenceStamp.order(of: container, in: db)
            for operation in pending.operations {
                switch operation {
                case .insert(let block, let after):
                    guard try Self.setBlockState(block, to: "live", from: "proposed", in: db) else { continue }
                    let place = try Self.index(after: after, in: order, of: container, in: db) ?? order.count
                    order.insert(try Self.blockKey(of: block, in: db), at: place)
                case .replace(let old, let new):
                    guard try Self.setBlockState(old, to: "replaced", from: "live", in: db) else {
                        try Self.setBlockState(new, to: "removed", from: "proposed", in: db)
                        continue
                    }
                    try Self.setBlockState(new, to: "live", from: "proposed", in: db)
                    let (oldKey, newKey) = (try Self.blockKey(of: old, in: db), try Self.blockKey(of: new, in: db))
                    order = order.map { $0 == oldKey ? newKey : $0 }
                case .remove(let old):
                    guard try Self.setBlockState(old, to: "removed", from: "live", in: db) else { continue }
                    let oldKey = try Self.blockKey(of: old, in: db)
                    order.removeAll { $0 == oldKey }
                }
            }
            try EvidenceStamp.replaceOrder(of: container, with: order, in: db)
            try decidePageProposal(id, as: "accepted", on: surface, in: db)
        }
    }

    /// Throws a pending proposal away, in one transaction: its proposed blocks are deleted, and the proposal is kept as
    /// discarded, with the surface the person decided on.
    public func discard(proposal id: PageProposalID, surface: MarkSurface) throws {
        try writer.write { db in try discardProposal(id, on: surface, in: db) }
    }

    /// The person removes a live block of a machine from the page. The block stays as history, as `removed`, with the
    /// surface the person did it on.
    public func removeBlock(_ block: MachineBlockID, surface: MarkSurface) throws {
        try writer.write { db in
            let page = try Self.livePage(of: block, in: db)
            guard try Self.setBlockState(block, to: "removed", from: "live", in: db) else {
                throw PageStoreError.notLive(block)
            }
            try db.execute(
                sql: "UPDATE machine_block SET removed_surface = ? WHERE id = ?",
                arguments: [surface.rawValue, block.rawValue])
            let key = try Self.blockKey(of: block, in: db)
            let container = try Self.container(of: page)
            let order = try EvidenceStamp.order(of: container, in: db).filter { $0 != key }
            try EvidenceStamp.replaceOrder(of: container, with: order, in: db)
        }
    }

    /// The person moves a live block of a machine to stand after `after`, or first on the page when it is nil.
    public func moveBlock(_ block: MachineBlockID, after: PageBlockRef?) throws {
        try writer.write { db in
            let page = try Self.livePage(of: block, in: db)
            let key = try Self.blockKey(of: block, in: db)
            let container = try Self.container(of: page)
            var order = try EvidenceStamp.order(of: container, in: db).filter { $0 != key }
            let place =
                try after.map { try Self.index(after: $0, in: order, of: container, in: db) ?? order.count } ?? 0
            order.insert(key, at: place)
            try EvidenceStamp.replaceOrder(of: container, with: order, in: db)
        }
    }
}

/// A pending proposal as accept reads it.
private struct PendingRow {
    var page: WorkObjectID
    var operations: [StoredOperation]
}

extension Store {
    /// The container of a page's order: the container of its note, so the person's paragraphs and the machine's blocks
    /// stand in one order.
    static func container(of page: WorkObjectID) throws -> String {
        guard let note = NoteID(object: page) else { throw WorkObjectError.unknown(page) }
        return note.rawValue
    }

    fileprivate static func pending(_ id: PageProposalID, in db: Database) throws -> PendingRow {
        guard
            let row = try Row.fetchOne(
                db, sql: "SELECT object_id, ops FROM page_proposal WHERE id = ? AND state = 'pending'",
                arguments: [id])
        else { throw PageStoreError.notPending(id) }
        return PendingRow(page: row["object_id"], operations: try row.json("ops"))
    }

    /// Records the decision. A proposal that is not pending cannot be decided again.
    fileprivate func decidePageProposal(
        _ id: PageProposalID, as state: String, on surface: MarkSurface, in db: Database
    ) throws {
        try db.execute(
            sql: """
                UPDATE page_proposal SET state = ?, decided_at = ?, surface = ? WHERE id = ? AND state = 'pending'
                """, arguments: [state, clock().stored, surface.rawValue, id])
        guard db.changesCount == 1 else { throw PageStoreError.notPending(id) }
    }

    fileprivate func discardProposal(_ id: PageProposalID, on surface: MarkSurface, in db: Database) throws {
        try decidePageProposal(id, as: "discarded", on: surface, in: db)
        try db.execute(sql: "DELETE FROM machine_block WHERE proposal_id = ? AND state = 'proposed'", arguments: [id])
    }

    /// Moves a block from one state to another. False when the block is not in the first state.
    @discardableResult
    fileprivate static func setBlockState(
        _ block: MachineBlockID, to state: String, from current: String, in db: Database
    ) throws -> Bool {
        try db.execute(
            sql: "UPDATE machine_block SET state = ? WHERE id = ? AND state = ?",
            arguments: [state, block.rawValue, current])
        return db.changesCount == 1
    }

    fileprivate static func blockKey(of block: MachineBlockID, in db: Database) throws -> Data {
        guard
            let key = try Data.fetchOne(
                db, sql: "SELECT entity_key FROM machine_block WHERE id = ?", arguments: [block.rawValue])
        else { throw PageStoreError.notLive(block) }
        return key
    }

    /// The page of a live block.
    fileprivate static func livePage(of block: MachineBlockID, in db: Database) throws -> WorkObjectID {
        guard
            let page = try String.fetchOne(
                db, sql: "SELECT object_id FROM machine_block WHERE id = ? AND state = 'live'",
                arguments: [block.rawValue])
        else { throw PageStoreError.notLive(block) }
        return page
    }

    /// Where a block goes that follows `place`: the position after it in `order`. A paragraph that was joined to another
    /// is followed to the paragraph that holds its words now. Nil when the place is gone from the order.
    fileprivate static func index(after place: PageBlockRef?, in order: [Data], of container: String, in db: Database)
        throws -> Int?
    {
        guard let place else { return nil }
        var key = try anchorKey(place, of: container, in: db)
        var seen: Set<Data> = []
        while !order.contains(key), seen.insert(key).inserted,
            let next = try Data.fetchOne(
                db, sql: "SELECT into_key FROM entity_supersede WHERE entity_key = ?", arguments: [key])
        {
            key = next
        }
        return order.firstIndex(of: key).map { $0 + 1 }
    }

    private static func anchorKey(_ place: PageBlockRef, of container: String, in db: Database) throws -> Data {
        switch place {
        case .note(let block):
            return Data(try EntityKey.note(noteID: container, blockID: block.rawValue).bytes)
        case .machine(let block): return try blockKey(of: block, in: db)
        }
    }

    fileprivate static func insertProposal(
        _ db: Database, _ staged: StagedProposal, of proposal: PageProposal, page: WorkObjectID, machine: Int64,
        request: Data, at now: Date
    ) throws -> PageProposalID {
        try db.execute(
            sql: """
                INSERT INTO page_proposal(object_id, machine_id, run_id, request_line, note, ops, state, at)
                VALUES (?,?,?,?,?,?,'pending',?)
                """,
            arguments: [
                page, machine, proposal.run, request, proposal.note, try Coding.json(staged.operations), now.stored,
            ])
        return db.lastInsertedRowID
    }
}

/// What a cite stands for in the store: the line it rests on, and, for a fact, the fact and the span of its quote.
struct ResolvedCite {
    var item: Int64?
    var line: Data
    var span: Range<Int>?

    init(item: Int64? = nil, line: Data, span: Range<Int>? = nil) {
        self.item = item
        self.line = line
        self.span = span
    }
}

/// What every cite of a proposal's blocks stands for, found once for the whole proposal.
struct CiteContext {
    let request: Data
    let facts: [Int64: QuotedLine]
    let paragraphs: [BlockID: Data]

    init(_ db: Database, page: WorkObjectID, request: Data, blocks: [MachineBlock]) throws {
        self.request = request
        facts = try Queries.quotedLines(db, ofFacts: blocks.flatMap(\.grounds).compactMap(\.fact))
        paragraphs = try Queries.paragraphLines(db, in: try Store.container(of: page))
    }

    func resolve(_ cite: PageCite) throws -> ResolvedCite {
        switch cite {
        case .request: return ResolvedCite(line: request)
        case .fact(let id):
            guard let quote = facts[id] else { throw PageStoreError.noQuoteLine(fact: id) }
            return ResolvedCite(item: id, line: quote.line, span: quote.span)
        case .note(let block):
            guard let line = paragraphs[block] else { throw PageStoreError.noParagraph(block) }
            return ResolvedCite(line: line)
        }
    }
}

extension Store {
    fileprivate static func insertBlock(
        _ db: Database, _ id: MachineBlockID, _ block: MachineBlock, page: WorkObjectID, proposal: PageProposalID,
        run: RunID, _ context: CiteContext, at now: Date
    ) throws {
        let cites = try block.grounds.map(context.resolve)
        try db.execute(
            sql: """
                INSERT INTO machine_block(id, object_id, entity_key, kind, spec, state, made_by_run, proposal_id, label,
                    made_at) VALUES (?,?,?,?,?,'proposed',?,?,?,?)
                """,
            arguments: [
                id.rawValue, page, Data(try EntityKey.machineBlock(objectID: page, blockID: id.rawValue).bytes),
                block.kind.rawValue, try Coding.json(block), run, proposal, try label(of: block, citing: cites, in: db),
                now.stored,
            ])
        for (position, cite) in cites.enumerated() {
            try db.execute(
                sql: """
                    INSERT INTO machine_block_cite(block_id, position, item_id, line_id, quote_start, quote_end)
                    VALUES (?,?,?,?,?,?)
                    """,
                arguments: [id.rawValue, position, cite.item, cite.line, cite.span?.lowerBound, cite.span?.upperBound])
        }
    }

    /// Who may read the block, as JSON: the join of the labels of the lines it cites and of the facts it cites, by
    /// `Standing`. Nil for a block that has no label of its own, and for one whose sources are not all known.
    private static func label(of block: MachineBlock, citing cites: [ResolvedCite], in db: Database) throws -> String? {
        guard block.hasLabel else { return nil }
        let lines = try cites.compactMap { try Queries.storedLine(db, id: $0.line) }.map(\.evidence)
        let facts = try cites.compactMap(\.item).compactMap { try Queries.item(db, id: $0) }
        return try Standing(citing: lines, facts: facts, window: []).label.map { try Coding.json(StoredLabel($0)) }
    }
}
