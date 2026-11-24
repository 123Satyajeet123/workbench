import Foundation

@testable import WorkbenchCore
@testable import WorkbenchUI

/// What the page model loaded for the machine, and, by a query of its own, where the store files the machine's facts.
extension LiveSession {
    func printSetup() throws {
        let store = app.store
        guard let pageObject = pip.machine.page, let page = try store.queries.workObject(pageObject) else {
            throw LiveFailure("the machine has no page object")
        }
        let parent = try store.queries.parent(of: pageObject).flatMap(store.queries.workObject)
        print("machine: \(pip.name) (id \(pip.machine.id), task \(pip.spec.task))")
        print("page object: \(page.name) \(page.id)")
        print("parent folder: \(parent.map { "\($0.name) \($0.id)" } ?? "none")")
        print("model: \(try ModelChoice.saved(in: store).title), billing \(Billing.saved(in: store).rawValue)")
        print("facts the page model loaded: \(self.page.facts.count)")
        print("  query: queries.facts(in: parent of page, includeChildren: true)")
        for fact in self.page.facts.prefix(3) { print("  fact \(fact.id.map(String.init) ?? "?") \(describe(fact))") }
        let filed = try store.queries.items(of: pip.spec.task, since: WorkDay(containing: .distantPast))
        let homes = try filed.compactMap(\.id).map { try store.queries.home(of: $0).map(\.name) ?? "no home" }
        print("facts of task \(pip.spec.task) in the store: \(filed.count)")
        for (home, count) in Dictionary(grouping: homes, by: { $0 }).sorted(by: { $0.key < $1.key }) {
            print("  filed under \(home): \(count.count)")
        }
    }

    private func describe(_ fact: Item) -> String {
        let fields = fact.fields.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
        return "day \(fact.day), scope \(fact.scope), \(fields), quote \"\(fact.quote)\""
    }
}
