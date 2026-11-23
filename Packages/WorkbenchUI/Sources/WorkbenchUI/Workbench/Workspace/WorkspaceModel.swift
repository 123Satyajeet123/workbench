import Foundation
import Observation
import WorkbenchCore

/// The tree of the workspace as the sidebar shows it: the top level, the Private section, the levels loaded so far,
/// the objects that have children and the rows that are open. A level loads when its row opens. Also the person's
/// favourite and recent pages, kept in the store of the profile, so each person and the demo keep their own.
@Observable
final class WorkspaceModel {
    /// Recents lists this many pages, newest first.
    static let recentCount = 5
    static let privateNote = "Who can read a page follows its sources, not its folder."
    private static let favoritesKey = StateKey<[String]>.json("sidebar.favorites")
    private static let recentsKey = StateKey<[String]>.json("sidebar.recents")

    private(set) var levels: [WorkObjectID?: [WorkObject]] = [:]
    private(set) var parents: Set<WorkObjectID> = []
    private(set) var expanded: Set<WorkObjectID> = []
    /// Every object that is not archived, in the order of the tree with every row open.
    private(set) var treeOrder: [WorkObjectID] = []
    private(set) var favorites: [SidebarSelection] = []
    private(set) var recents: [SidebarSelection] = []
    /// The object whose children make the Private section. Nil only when the store could not make it.
    private(set) var privateSection: WorkObjectID?
    /// Said once when a move takes a page into or out of Private: the move changes no access.
    var notice: String?
    /// Changes on every refresh, so a page that shows part of the tree reads it again.
    private(set) var revision = 0
    let problems = ProblemSlot()

    @ObservationIgnored private let store: Store

    init(store: Store) {
        self.store = store
        problems.attempt("set up the workspace") {
            try store.seedWorkspace()
            privateSection = try store.privateSection().id
            favorites = try pages(Self.favoritesKey)
            recents = Array(try pages(Self.recentsKey).prefix(Self.recentCount))
        }
        refresh()
        expanded = parents.intersection(roots.map(\.id) + privateItems.map(\.id))
        refresh()
    }

    /// The top level of the workspace, without the Private section.
    var roots: [WorkObject] { (levels[nil] ?? []).filter { $0.id != privateSection } }

    var privateItems: [WorkObject] { privateSection.map(children(of:)) ?? [] }

    func children(of id: WorkObjectID) -> [WorkObject] { levels[id] ?? [] }

    func hasChildren(_ id: WorkObjectID) -> Bool { parents.contains(id) }

    func isExpanded(_ id: WorkObjectID) -> Bool { expanded.contains(id) }

    func setExpanded(_ id: WorkObjectID, _ isOpen: Bool) {
        if isOpen { expanded.insert(id) } else { expanded.remove(id) }
        refresh()
    }

    /// Reads the roots and every open level again.
    func refresh() {
        problems.attempt("read the workspace", clearing: true) {
            parents = try store.queries.workObjectsWithChildren()
            var loaded: [WorkObjectID?: [WorkObject]] = [
                nil: try store.queries.workObjects(parent: nil, includeArchived: false)
            ]
            for id in expanded.union(privateSection.map { [$0] } ?? []) {
                loaded[id] = try store.queries.workObjects(parent: id, includeArchived: false)
            }
            levels = loaded
            treeOrder = Self.treeOrder(
                of: try store.queries.everyWorkObject().filter { !$0.archived }, privateSection: privateSection)
        }
        revision += 1
    }

    /// Depth first, each level in its order: the workspace, then the Private section.
    static func treeOrder(of objects: [WorkObject], privateSection: WorkObjectID?) -> [WorkObjectID] {
        let levels = Dictionary(grouping: objects, by: \.parentID).mapValues { $0.sorted { $0.position < $1.position } }
        func subtree(_ object: WorkObject) -> [WorkObjectID] {
            [object.id] + (levels[object.id] ?? []).flatMap(subtree)
        }
        let top = levels[nil] ?? []
        return (top.filter { $0.id != privateSection } + top.filter { $0.id == privateSection }).flatMap(subtree)
    }

    /// The object of this id, archived or not, from the loaded levels or else from the store.
    func object(_ id: WorkObjectID) -> WorkObject? {
        levels.values.lazy.flatMap { $0 }.first { $0.id == id } ?? (try? store.queries.workObject(id))
    }

    /// The children of `id`, the archived ones too, read now.
    func contents(of id: WorkObjectID) -> [WorkObject] {
        var found: [WorkObject] = []
        problems.attempt("read the page") { found = try store.queries.workObjects(parent: id, includeArchived: true) }
        return found
    }

    /// The facts whose home is `id` or an object below it.
    func facts(in id: WorkObjectID) -> [Item] {
        var found: [Item] = []
        problems.attempt("read the facts of the page") {
            found = try store.queries.facts(in: id, includeChildren: true)
        }
        return found
    }

    /// Every object of the tree, archived ones too, for search.
    func everyObject() -> [WorkObject] {
        (try? store.queries.everyWorkObject()) ?? []
    }

    /// A new object of `type` under `parent`, named `name`, or `name 2` and on when a sibling has that name.
    @discardableResult
    func create(_ type: ObjectType, under parent: WorkObjectID?, name: String) -> WorkObject? {
        var made: WorkObject?
        problems.attempt("make the \(type.noun)") {
            let taken = Set(try store.queries.workObjects(parent: parent, includeArchived: false).map(\.name))
            let free = ([name] + (2...).lazy.map { "\(name) \($0)" }).first { !taken.contains($0) } ?? name
            made = try store.createWorkObject(type: type, parent: parent, name: free)
        }
        if let parent { expanded.insert(parent) }
        refresh()
        return made
    }

    func rename(_ id: WorkObjectID, to name: String) {
        problems.attempt("rename it") { try store.rename(id, to: name) }
        refresh()
    }

    func archive(_ id: WorkObjectID) {
        problems.attempt("archive it") { try store.archive(id) }
        refresh()
    }

    /// Moves the dragged objects under `parent`: before the row at `index` among its children, or last.
    func drop(_ ids: [WorkObjectID], into parent: WorkObjectID?, at index: Int? = nil) {
        let siblings = parent.map(children(of:)) ?? roots
        let before = index.flatMap { index in
            siblings.dropFirst(min(index, siblings.count)).first { !ids.contains($0.id) }?.id
        }
        let crossesPrivate = ids.contains { isPrivate($0) != isPrivate(parent) }
        problems.attempt("move it") {
            for id in ids { try store.move(id, under: parent, before: before) }
        }
        notice = crossesPrivate ? Self.privateNote : nil
        if let parent { expanded.insert(parent) }
        refresh()
    }

    /// Whether `id` is the Private section or stands below it.
    func isPrivate(_ id: WorkObjectID?) -> Bool {
        var next = id
        var seen: Set<WorkObjectID> = []
        while let current = next, seen.insert(current).inserted {
            if current == privateSection { return true }
            next = object(current)?.parentID
        }
        return false
    }

    func isFavorite(_ page: SidebarSelection) -> Bool { favorites.contains(page) }

    func toggleFavorite(_ page: SidebarSelection) {
        favorites = isFavorite(page) ? favorites.filter { $0 != page } : favorites + [page]
        save(favorites, Self.favoritesKey, "save your favourites")
    }

    /// Puts a page of the tree first among the recent pages. The fixed pages have rows of their own.
    func visit(_ page: SidebarSelection) {
        switch page {
        case .page, .machine: guard recents.first != page else { return }
        default: return
        }
        recents = Array(([page] + recents.filter { $0 != page }).prefix(Self.recentCount))
        save(recents, Self.recentsKey, "save your recent pages")
    }

    private func save(_ pages: [SidebarSelection], _ key: StateKey<[String]>, _ step: String) {
        problems.attempt(step) { try key.save(pages.map(\.rawValue), to: store) }
    }

    private func pages(_ key: StateKey<[String]>) throws -> [SidebarSelection] {
        (try key.load(from: store) ?? []).compactMap(SidebarSelection.init(rawValue:))
    }
}
