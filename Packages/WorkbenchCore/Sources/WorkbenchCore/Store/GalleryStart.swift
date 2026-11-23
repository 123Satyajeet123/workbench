import Foundation

/// What setting up a gallery template made.
public struct GalleryStart: Sendable, Equatable {
    public var folder: WorkObject
    /// Nil when the template starts no machine.
    public var machine: Machine?
}

extension Store {
    /// Sets up a gallery template: its folder, found when a live one of that name exists, and its machine with its page
    /// in that folder. The folder keeps the type of the objects it holds. Setting up the same template twice gives one
    /// folder and two machines.
    @discardableResult
    public func start(_ template: GalleryTemplate) throws -> GalleryStart {
        let folder = try writer.write { db in
            try Queries.workObjects(db, where: "id = ?", [try WorkObjectRows.folder(db, for: template.folder)])[0]
        }
        let machine = try template.machine.map {
            try createMachine(from: $0.spec, template: $0.id, name: $0.name, in: folder.id)
        }
        return GalleryStart(folder: folder, machine: machine)
    }
}
