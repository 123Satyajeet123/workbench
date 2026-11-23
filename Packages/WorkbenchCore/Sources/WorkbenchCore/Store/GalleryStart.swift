import Foundation

/// What setting up a gallery template made.
public struct GalleryStart: Sendable, Equatable {
    public var folder: WorkObject
    /// Nil when the template starts no machine.
    public var machine: Machine?
}

extension Store {
    /// Sets up a gallery template: its folder, found when a live one of that name exists, and its machine with its page
    /// in that folder. Setting up the same template twice gives one folder and two machines.
    @discardableResult
    public func start(_ template: GalleryTemplate) throws -> GalleryStart {
        let folder = try createWorkObject(type: ObjectTypes.folder, parent: nil, name: template.folder.name)
        let machine = try template.machine.map {
            try createMachine(from: $0.spec, template: $0.id, name: $0.name, in: folder.id)
        }
        return GalleryStart(folder: folder, machine: machine)
    }
}
