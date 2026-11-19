import Foundation
import Observation
import WorkbenchCore

/// Deals as shared work objects. Every act is an event by the founder, kept in the store and written to the
/// founder's own log in the team folder; teammates' logs are read back, so each Mac folds the same deals. An item
/// linked to a deal leaves the Mac only when every teammate can already read its source.
@Observable
final class DealsModel {
    private(set) var deals: [WorkObject] = []
    private(set) var unreadable: [String] = []
    private(set) var problem: String?

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let catalog: TeamCatalogModel

    init(store: Store, catalog: TeamCatalogModel) {
        self.store = store
        self.catalog = catalog
        refresh()
    }

    var me: String { catalog.me }
    var stages: [String] { WorkObject.dealStages }

    func deals(in stage: String) -> [WorkObject] { deals.filter { $0.stages.contains(stage) } }
    func deal(_ id: String) -> WorkObject? { deals.first { $0.id == id } }

    /// Reads teammates' logs into the store, then folds every event as the founder sees it.
    func refresh() {
        attempt("read the deals") {
            if let folder = catalog.folder {
                let read = WorkLog.read(from: folder)
                try store.append(read.events)
                unreadable = read.unreadable
            }
            deals = WorkObject.fold(try store.queries.workEvents(), viewer: me).filter {
                $0.kind == "deal" && !$0.archived
            }
        }
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

    /// A new stage replaces every standing one, so a move also settles a conflict.
    func move(_ deal: WorkObject, to stage: String) {
        add([.init(object: deal.id, kind: .stage, text: stage, replaces: deal.stageHeads)])
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

    /// Links a machine's item, with the audience of its source as it is now.
    func link(_ item: Item, from helper: HelperModel, to deal: String) async {
        do {
            let found = try await catalog.readers(of: helper)
            let missing = Set(found.missing.map(\.name))
            let audience = [me] + found.recipients.map(\.name).filter { !missing.contains($0) }
            add([
                .init(
                    object: deal, kind: .link, item: LinkedItem(machine: helper.machine, item: item, audience: audience)
                )
            ])
        } catch {
            problem = "Could not link the item: \(error.localizedDescription)"
        }
    }

    /// A deal named after the item's title field, with the item linked.
    @discardableResult
    func newDeal(from item: Item, of helper: HelperModel) async -> String? {
        guard let id = create(title: item[helper.spec.title].cleaned ?? item.quote) else { return nil }
        await link(item, from: helper, to: id)
        return id
    }

    func dismissProblem() { problem = nil }

    /// What the founder's events look like before the store gives them an id and a clock.
    struct Draft {
        var object: String
        var kind: WorkEvent.Kind
        var text = ""
        var replaces: [String] = []
        var item: LinkedItem?
    }

    private func add(_ drafts: [Draft]) {
        attempt("save the change") {
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

    /// Rewrites the founder's log in the team folder. A link goes only when every current teammate is in its item's
    /// audience; otherwise it stays on this Mac.
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

    private func attempt(_ step: String, _ work: () throws -> Void) {
        do {
            try work()
        } catch {
            problem = "Could not \(step): \(error.localizedDescription)"
        }
    }
}
