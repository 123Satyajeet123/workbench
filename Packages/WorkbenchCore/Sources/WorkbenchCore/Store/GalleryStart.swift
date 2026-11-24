import Foundation

/// What setting up a gallery template made.
public struct GalleryStart: Sendable, Equatable {
    public var folder: WorkObject
    /// Nil when the template starts no machine.
    public var machine: Machine?
    /// What the person must still do on the page: choose a source, set a value. Nothing is granted for them.
    public var prompts: [GalleryTemplate.StartBlock]
}

/// Why a gallery template was not set up.
public enum GalleryStartError: Error, Equatable, LocalizedError {
    case needs(template: String, GalleryTemplate.Need)

    public var errorDescription: String? {
        switch self {
        case .needs(let template, let need): "\(template) needs \(need.words)."
        }
    }
}

extension Store {
    /// Sets up a gallery template: its folder, found when a live one of that name exists, and its machine with its page
    /// in that folder. The folder keeps the type of the objects it holds. The machine shows its facts in the view the
    /// template names. A source is never granted here: the template's pickers come back as prompts for the person.
    /// Setting up the same template twice gives one folder and two machines.
    /// - Parameters:
    ///   - name: The machine's name, when it is not the template's own.
    ///   - overrides: The values a team sets in the machine's spec.
    ///   - having: What the app can give. A template that needs more is refused.
    @discardableResult
    public func start(
        _ template: GalleryTemplate, name: String? = nil, overrides: SpecOverrides = SpecOverrides(),
        having: Set<GalleryTemplate.Need> = []
    ) throws -> GalleryStart {
        if let missing = template.needs.subtracting(having).min(by: { $0.rawValue < $1.rawValue }) {
            throw GalleryStartError.needs(template: template.name, missing)
        }
        let folder = try writer.write { db in
            try Queries.workObjects(db, where: "id = ?", [try WorkObjectRows.folder(db, for: template.folder)])[0]
        }
        let machine = try template.machine.map {
            try createMachine(
                from: template.defaultView(of: overrides.applied(to: $0.spec)), template: template.id,
                name: name ?? $0.name, in: folder.id)
        }
        return GalleryStart(folder: folder, machine: machine, prompts: template.prompts)
    }
}
