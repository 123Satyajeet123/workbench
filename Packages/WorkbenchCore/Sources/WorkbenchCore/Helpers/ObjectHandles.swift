import Foundation

/// The live work objects one reading shows the model, each with a handle (O1, O2, …). A model names an object only by
/// one of these handles. Code turns the handle back into the id and checks the type of the object, so a handle the
/// model was not shown, or one of another type, names nothing. This is the one way a reply refers to an object, for
/// a field of the kind `objectRef` and for the home of a fact.
struct ObjectHandles: Sendable, Equatable {
    /// What a handle in a reply names.
    enum Choice: Sendable, Equatable {
        case none
        case object(WorkObjectID)
        /// A handle that names no object of the types allowed.
        case refused(String)
    }

    /// The types a fact may be filed under.
    static let placeTypes = ObjectTypes.homes.map(\.id)

    let objects: [WorkObject]

    init(_ objects: [WorkObject] = []) {
        self.objects = objects
    }

    static func handle(_ index: Int) -> String { "O\(index + 1)" }

    /// The objects of `types`, one per line with its handle. Empty when there is none.
    func listing(of types: [TypeID], title: String) -> String {
        let lines = objects.enumerated().filter { types.contains($0.element.type.id) }.map { index, object in
            "\(Self.handle(index)) \(object.type.noun) \(object.name)"
        }
        return lines.isEmpty ? "" : title + ":\n" + lines.joined(separator: "\n") + "\n\n"
    }

    func has(_ types: [TypeID]) -> Bool { objects.contains { types.contains($0.type.id) } }

    /// The object a handle names, when it is one of `types`. An empty handle names none, and is not refused.
    func resolve(_ handle: String, among types: [TypeID]) -> Choice {
        guard !handle.isEmpty else { return .none }
        guard handle.first == "O", let number = Int(handle.dropFirst()), objects.indices.contains(number - 1),
            types.contains(objects[number - 1].type.id)
        else { return .refused(handle) }
        return .object(objects[number - 1].id)
    }
}
