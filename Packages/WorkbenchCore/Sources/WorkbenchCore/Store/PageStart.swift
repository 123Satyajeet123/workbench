import Foundation
import GRDB
import Kernel
import Lines

extension Store {
    /// Gives the page of a machine the facts block of its template, once. A page that ever held a machine block, in any
    /// state, is left as it is: a block the person removed stays as history, so it is never added again. The block
    /// goes through the page gate and is stored live, with no run and no proposal, last in the page's order.
    public func startPage(of machine: Machine) throws {
        try writer.write { db in try startPage(db, of: machine) }
    }

    func startPage(_ db: Database, of machine: Machine) throws {
        guard let page = machine.page,
            try !Bool.fetchOne(
                db, sql: "SELECT EXISTS (SELECT 1 FROM machine_block WHERE object_id = ?)", arguments: [page])!,
            let view = GalleryTemplate.of(id: machine.template)?.startFactsView(of: machine.spec)
        else { return }
        let gate = PageGate(catalog: PageCatalog(spec: machine.spec, items: []))
        let (placed, verdicts) = gate.apply([.insert(.facts(view), after: nil)], to: MachinePage())
        guard verdicts.allSatisfy({ $0.refusal == nil }), let block = placed.blocks.first else { return }
        let key = try EntityKey.machineBlock(objectID: page, blockID: block.key.rawValue)
        try db.execute(
            sql: """
                INSERT INTO machine_block(id, object_id, entity_key, kind, spec, state, made_at)
                VALUES (?,?,?,?,?,'live',?)
                """,
            arguments: [
                block.key.rawValue, page, Data(key.bytes), block.value.kind.rawValue, try Coding.json(block.value),
                clock().stored,
            ])
        let container = try Self.container(of: page)
        let order = try EvidenceStamp.order(of: container, in: db) + [Data(key.bytes)]
        try EvidenceStamp.replaceOrder(of: container, with: order, in: db)
        try Self.derive([try DerivedSources.ofBlock(block.key.rawValue, in: db)], at: clock(), in: db)
    }
}
