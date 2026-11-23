import WorkbenchCore

extension WorkObject {
    /// The SF Symbol of the object's kind. A kind with no symbol of its own shows as a page.
    var symbol: String { Self.symbols[kind] ?? "doc.text" }

    /// What the object is, in a word or two: "Folder", or "Archived folder".
    var noun: String { archived ? "Archived \(type.noun)" : type.noun.capitalized }

    private static let symbols = [
        ObjectTypes.folder.id: "folder", ObjectTypes.page.id: "doc.text", ObjectTypes.deal.id: "rectangle.3.group",
        ObjectTypes.project.id: "square.stack.3d.up", ObjectTypes.company.id: "building.2",
        ObjectTypes.machinePage.id: "gearshape.2",
    ]
}

extension Crew {
    /// The machine whose page is `object`, if one is.
    func helper(page object: WorkObjectID) -> HelperModel? { machines.first { $0.machine.page == object } }

    /// The page the window opens for a row of the tree: a machine's own page for a machine's page, else the object's.
    func page(of object: WorkObject) -> SidebarSelection {
        helper(page: object.id).map { .machine($0.machine.id) } ?? .page(object.id)
    }

    /// The object of the tree that a page of the window shows, if one does.
    func object(of page: SidebarSelection, in workspace: WorkspaceModel) -> WorkObject? {
        switch page {
        case .page(let id): workspace.object(id)
        case .machine(let id): helper(id: id)?.machine.page.flatMap(workspace.object)
        default: nil
        }
    }
}
