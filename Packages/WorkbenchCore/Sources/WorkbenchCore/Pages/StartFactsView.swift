import Foundation

extension FactsView {
    /// The facts a machine of `spec` shows in `view`: the layout that view draws, grouped by the field it groups by.
    init(of spec: HelperSpec, showing view: HelperSpec.View) {
        let noun = spec.itemsNoun
        let title = noun.prefix(1).uppercased() + noun.dropFirst()
        switch view {
        case .table:
            let named = spec.fields.contains { $0.name == spec.title } ? [spec.title] : []
            self.init(title: title, layout: .table, columns: named + [PageCatalog.quoteColumn])
        case .timeline: self.init(title: title, layout: .list)
        case .board(let field, _): self.init(title: title, groupBy: field, layout: .board)
        case .grouped(let field), .checklist(let field): self.init(title: title, groupBy: field, layout: .list)
        }
    }
}

extension GalleryTemplate {
    /// The facts block a machine of this template starts its page with: the first facts block that names the template's
    /// machine, in a view the machine's spec can fill. Nil when the template names none.
    func startFactsView(of spec: HelperSpec) -> FactsView? {
        guard let task = machine?.spec.task else { return nil }
        return blocks.lazy.compactMap { block -> FactsView? in
            guard case .facts(let blockTask, let name) = block, blockTask == task, let view = spec.views[name] else {
                return nil
            }
            return FactsView(of: spec, showing: view)
        }.first
    }
}
