import Foundation

extension Store {
    static let workspaceSeededKey = "workspace.seeded"
    static let rootsFiledKey = "workspace.rootsFiled"

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

    /// Once per store: each root that has a place moves to the end of it, in the order of the roots. A deal's place is
    /// the folder of the machine that made it, else the one folder that holds deals. Objects made before they had a
    /// place were left among the roots. A later call changes nothing, so an object the person moves back among the
    /// roots stays there.
    public func fileRootsInTheirFolders() throws {
        guard try queries.state(forKey: Self.rootsFiledKey) == nil else { return }
        for root in try writer.read(WorkObjectRows.rootsWithAPlace) { try move(root.object, under: root.place) }
        try saveState("filed", forKey: Self.rootsFiledKey)
    }
}
