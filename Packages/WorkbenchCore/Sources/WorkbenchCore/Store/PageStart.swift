import Foundation
import GRDB
import Kernel
import Lines

extension Store {
    /// Gives the page of a machine its first form once: the blocks `FirstForm` works out from the machine's spec, each
    /// through the page gate and stored live, with no run and no proposal, in the page's order.
    ///
    /// A page is started when it holds no machine block in any state, and also when it holds only the one facts block
    /// that this call wrote in its earlier form and that nobody has touched. That is decided from stored rows: the page
    /// has exactly one `machine_block` row, live, made by no run and no proposal, whose spec is the template's own
    /// start view; the page has no `page_proposal` row; and its order holds that block alone, so no paragraph of the
    /// person stands on it. Any other page is left as it is: a block the person removed, replaced or moved, a block a
    /// proposal brought, or a paragraph the person wrote each leave a row or an order entry that fails the test. A page
    /// that was started holds three or more rows, so a second call changes nothing.
    public func startPage(of machine: Machine) throws {
        try writer.write { db in try startPage(db, of: machine) }
    }

    func startPage(_ db: Database, of machine: Machine) throws {
        guard let page = machine.page,
            let template = GalleryTemplate.of(id: machine.template)?.startFactsView(of: machine.spec),
            let old = try untouchedStart(db, page: page, template: template)
        else { return }
        let gate = PageGate(catalog: PageCatalog(spec: machine.spec, items: []))
        let (placed, verdicts) = gate.apply(
            FirstForm.views(of: machine.spec).map { .insert(.facts($0), after: nil) }, to: MachinePage())
        guard verdicts.allSatisfy({ $0.refusal == nil }) else { return }
        let container = try Self.container(of: page)
        let keys = try placed.order.compactMap { place -> Data? in
            guard case .machine(let id) = place, let block = placed.blocks[id] else { return nil }
            return try insertLive(block, as: id, on: page, in: db)
        }
        var order = try EvidenceStamp.order(of: container, in: db)
        if let old {
            try db.execute(sql: "UPDATE machine_block SET state = 'replaced' WHERE id = ?", arguments: [old.id])
            order = order.flatMap { $0 == old.key ? keys : [$0] }
        } else {
            order += keys
        }
        try EvidenceStamp.replaceOrder(of: container, with: order, in: db)
        let ids = try String.fetchAll(
            db, sql: "SELECT id FROM machine_block WHERE object_id = ? AND state = 'live'", arguments: [page])
        try Self.derive(try ids.map { try DerivedSources.ofBlock($0, in: db) }, at: clock(), in: db)
    }

    /// Writes a block as live, made by no run and by no proposal: the person's own or the start's. Returns its key.
    func insertLive(_ block: MachineBlock, as id: MachineBlockID, on page: WorkObjectID, in db: Database) throws -> Data
    {
        let key = Data(try EntityKey.machineBlock(objectID: page, blockID: id.rawValue).bytes)
        try db.execute(
            sql: """
                INSERT INTO machine_block(id, object_id, entity_key, kind, spec, state, made_at)
                VALUES (?,?,?,?,?,'live',?)
                """,
            arguments: [id.rawValue, page, key, block.kind.rawValue, try Coding.json(block), clock().stored])
        return key
    }

    /// What a page that may be started holds: `.some(nil)` for a page with no machine block at all, `.some(row)` for a
    /// page with only the template's own start block, untouched; nil for any other page.
    private func untouchedStart(_ db: Database, page: WorkObjectID, template: FactsView) throws -> StartBlock?? {
        let rows = try Row.fetchAll(
            db,
            sql:
                "SELECT id, entity_key, kind, spec, state, made_by_run, proposal_id FROM machine_block WHERE object_id = ?",
            arguments: [page])
        guard !rows.isEmpty else { return .some(nil) }
        let proposals = try Int.fetchOne(
            db, sql: "SELECT COUNT(*) FROM page_proposal WHERE object_id = ?", arguments: [page])!
        guard rows.count == 1, proposals == 0, let row = rows.first, row["state"] as String == "live",
            (row["made_by_run"] as Int64?) == nil, (row["proposal_id"] as Int64?) == nil,
            row["kind"] as String == MachineBlockKind.facts.rawValue,
            row["spec"] as String == (try Coding.json(MachineBlock.facts(template)))
        else { return nil }
        let key: Data = row["entity_key"]
        let order = try EvidenceStamp.order(of: try Self.container(of: page), in: db)
        guard order == [key] else { return nil }
        return .some(StartBlock(id: row["id"], key: key))
    }
}

private struct StartBlock {
    var id: String
    var key: Data
}
