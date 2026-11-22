import Foundation
import Observation
import WorkbenchCore

@Observable
final class DealsModel {
    private(set) var deals: [WorkObject] = []
    private(set) var digests: [String: DealDigest] = [:]
    private(set) var unreadable: [String] = []
    let problems = ProblemSlot()
    var problem: String? { problems.text }

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let catalog: TeamCatalogModel

    init(store: Store, catalog: TeamCatalogModel) {
        self.store = store
        self.catalog = catalog
        refresh()
    }

    var me: String { catalog.me }
    var stages: [String] { WorkObject.dealStages }

    var columns: [DealBoard.Column] { DealBoard.columns(of: deals, stages: stages) }
    func deals(in stage: String) -> [WorkObject] { deals.filter { $0.stages.contains(stage) } }
    func deal(_ id: String) -> WorkObject? { deals.first { $0.id == id } }

    func refresh() {
        problems.attempt("read the deals") {
            if let folder = catalog.folder {
                let read = WorkLog.read(from: folder)
                try store.append(read.events)
                unreadable = read.unreadable
            }
            deals = WorkObject.fold(try store.queries.workEvents(), viewer: me).filter {
                $0.kind == "deal" && !$0.archived
            }
            let machines = try store.queries.machines()
            let actions = try store.queries.dealActions()
            let reader = DealDigestReader(store: store, me: me)
            digests = Dictionary(
                uniqueKeysWithValues: try deals.map {
                    ($0.id, try reader.digest(of: $0, machines: machines, actions: actions))
                })
        }
        settleActions()
    }

    private func settleActions() {
        guard let actions = try? store.queries.dealActions() else { return }
        let settled = DealAction.settled(deals, actions: actions)
        add(settled.map { .init(object: $0.id, kind: .stage, text: WorkObject.afterAction, replaces: $0.stageHeads) })
    }

    @discardableResult
    func create(title: String) -> String? {
        guard let title = title.cleaned else { return nil }
        let id = UUID().uuidString
        add([
            .init(object: id, kind: .create, text: "deal"), .init(object: id, kind: .title, text: title),
            .init(object: id, kind: .stage, text: stages[0]),
        ])
        return id
    }

    func move(_ deal: WorkObject, to stage: String) {
        guard stage != WorkObject.actionRequired else { return }
        problems.attempt("drop the action") { try store.dropActions(of: deal.id) }
        add([.init(object: deal.id, kind: .stage, text: stage, replaces: deal.stageHeads)])
    }

    func requireAction(_ deal: WorkObject, what: String, due: WorkDay) {
        guard what.cleaned != nil else { return }
        problems.attempt("save the action") { try store.requireAction(of: deal, what: what, due: due, owner: me) }
        add([.init(object: deal.id, kind: .stage, text: WorkObject.actionRequired, replaces: deal.stageHeads)])
    }

    func finishAction(of deal: WorkObject) {
        guard let action = digests[deal.id]?.action else { return }
        problems.attempt("finish the action") { try store.apply(DealAction.lifecycle.closing([action])) }
        refresh()
    }

    func rename(_ deal: WorkObject, to title: String) {
        guard let title = title.cleaned else { return }
        add([.init(object: deal.id, kind: .title, text: title)])
    }

    func note(_ deal: WorkObject, _ text: String) {
        guard let text = text.cleaned else { return }
        add([.init(object: deal.id, kind: .note, text: text)])
    }

    func claim(_ deal: WorkObject) { add([.init(object: deal.id, kind: .claim)]) }
    func release(_ deal: WorkObject) { add([.init(object: deal.id, kind: .release)]) }
    func archive(_ deal: WorkObject) { add([.init(object: deal.id, kind: .archive)]) }

    func link(_ item: Item, from helper: HelperModel, to deal: String) async {
        await problems.attempt("link the item") {
            let found = try await catalog.readers(of: helper)
            let missing = Set(found.missing.map(\.name))
            let audience = [me] + found.recipients.map(\.name).filter { !missing.contains($0) }
            add([
                .init(
                    object: deal, kind: .link, item: LinkedItem(machine: helper.machine, item: item, audience: audience)
                )
            ])
        }
    }

    @discardableResult
    func newDeal(from item: Item, of helper: HelperModel) async -> String? {
        guard let id = create(title: item[helper.spec.title].cleaned ?? item.quote) else { return nil }
        await link(item, from: helper, to: id)
        return id
    }

    struct Draft {
        var object: String
        var kind: WorkEvent.Kind
        var text = ""
        var replaces: [String] = []
        var item: LinkedItem?
    }

    private func add(_ drafts: [Draft]) {
        guard !drafts.isEmpty else { return }
        problems.attempt("save the change") {
            let first = try store.queries.nextClock()
            let events = drafts.enumerated().map { index, draft in
                WorkEvent(
                    object: draft.object, author: me, clock: first + index, at: store.clock(), kind: draft.kind,
                    text: draft.text, replaces: draft.replaces, item: draft.item)
            }
            try store.append(events)
            try publish()
        }
        refresh()
    }

    private func publish() throws {
        guard let folder = catalog.folder else { return }
        let teammates = Set((try store.queries.team()?.people ?? []).filter { !$0.isMe }.map(\.name))
        let mine = try store.queries.workEvents().filter { event in
            guard event.author == me else { return false }
            guard let item = event.item else { return true }
            return teammates.isSubset(of: Set(item.audience))
        }
        try WorkLog.write(mine, author: me, to: folder)
    }

}
