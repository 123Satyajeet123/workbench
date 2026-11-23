import Foundation

extension Store {
    static let workspaceSeededKey = "workspace.seeded"

    /// The object whose children make the Private section, made when the store has none.
    @discardableResult
    public func privateSection() throws -> WorkObject {
        try createWorkObject(type: ObjectTypes.privateSection, parent: nil, name: "Private")
    }

    /// Once per store: a Team folder for the org's teammates at the top level, when there is none. The folders that
    /// are already at the top level stay there, and Private starts empty. A later call changes nothing, so a folder the
    /// person renamed or archived does not come back.
    public func seedWorkspace() throws {
        guard try queries.state(forKey: Self.workspaceSeededKey) == nil else { return }
        try createWorkObject(type: ObjectTypes.folder, parent: nil, name: "Team")
        try saveState("seeded", forKey: Self.workspaceSeededKey)
    }
}
