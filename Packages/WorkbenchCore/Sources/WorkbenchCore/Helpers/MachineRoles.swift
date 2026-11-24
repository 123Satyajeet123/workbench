import Foundation

/// What a machine does, read from its spec. Code asks for a role and never for a template or a task name.
extension HelperSpec {
    /// Its facts open and close, so a person can keep, answer or drop them.
    public var keepsFacts: Bool { lifecycle != nil }

    /// It rates what it reads against criteria.
    public var rates: Bool { criteria != nil }

    /// Its facts only list: they do not open and close, follow another machine, or belong to the screen, to a rating or
    /// to a feed that has a place of its own. Today lists them under the machine's name.
    public var listsFacts: Bool {
        lifecycle == nil && !needsFollowed && !readsScreen && !rates && source.givesDaysOfLines
    }

    /// It reads the claims of a deal's pitch, and checks them against the claim types it lists.
    public var checksClaims: Bool { claimTypes != nil }

    /// It reads what the person did on the screen.
    public var readsScreen: Bool { source.consent == .screen }

    /// The facts that no machine of the crew keeps, under the name their keeper shows.
    public static let withoutMachine: [(name: String, spec: HelperSpec)] = [("Echo", .callFollowUps)]
}

extension Collection where Element == Machine {
    public func with(_ role: KeyPath<HelperSpec, Bool>) -> [Machine] { filter { $0.spec[keyPath: role] } }

    /// The machine with `role` that the work of a deal belongs to, found by data in this order: the machine of the item
    /// the deal links first; the machine nearest to the deal's folder (the folder, then the folders above it); the oldest
    /// machine with the role in the deal's team. A machine of another team never answers for the deal. Nil when no
    /// machine has the role.
    public func owner(
        of role: KeyPath<HelperSpec, Bool>, linkedTasks: [String], folder: WorkObjectID?, in tree: FolderTree
    ) -> Machine? {
        let candidates = with(role)
        let linked = linkedTasks.lazy.compactMap { task in candidates.first { $0.task == task } }.first
        return linked ?? tree.nearestOrFirstSharingTeam(in: candidates, with: folder, folderOf: \.folder)
    }
}

extension Queries {
    /// The machine with `role` that the work of `deal` belongs to; see `Collection.owner`.
    public func owner(of deal: WorkObject, role: KeyPath<HelperSpec, Bool>) throws -> Machine? {
        try machines().owner(
            of: role, linkedTasks: deal.items.compactMap(\.item.task), folder: try parent(of: deal.id),
            in: try folderTree())
    }
}
