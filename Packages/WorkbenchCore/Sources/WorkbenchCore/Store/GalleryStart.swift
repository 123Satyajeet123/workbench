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

extension GalleryTemplate {
    /// Why the app cannot set this template up with what it has, or nil when it can.
    func refusal(having: Set<Need>) -> GalleryStartError? {
        needs.subtracting(having).min(by: { $0.rawValue < $1.rawValue }).map { .needs(template: name, $0) }
    }
}

extension Store {
    /// Sets up a gallery template: its folder, found when a live one of that name exists under `parent` (a root when
    /// nil), and its machine with its page in that folder. The folder keeps the type of the objects it holds. The
    /// machine shows its facts in the view the template names. A source is never granted here: the template's pickers
    /// come back as prompts for the person.
    /// Setting up the same template twice under one parent gives one folder and two machines. A folder of another
    /// parent is never touched.
    /// - Parameters:
    ///   - parent: The folder the template's folder goes under: the folder of a team.
    ///   - name: The machine's name, when it is not the template's own.
    ///   - overrides: The values a team sets in the machine's spec.
    ///   - having: What the app can give. A template that needs more is refused.
    @discardableResult
    public func start(
        _ template: GalleryTemplate, parent: WorkObjectID? = nil, name: String? = nil,
        overrides: SpecOverrides = SpecOverrides(),
        having: Set<GalleryTemplate.Need> = []
    ) throws -> GalleryStart {
        if let refusal = template.refusal(having: having) { throw refusal }
        let folder = try writer.write { db in
            try Queries.workObjects(
                db, where: "id = ?", [try WorkObjectRows.folder(db, for: template.folder, parent: parent)])[0]
        }
        let machine = try template.machine.map {
            try createMachine(
                from: template.defaultView(of: overrides.applied(to: $0.spec)), template: template.id,
                name: name ?? $0.name, in: folder.id)
        }
        return GalleryStart(folder: folder, machine: machine, prompts: template.prompts)
    }
}
